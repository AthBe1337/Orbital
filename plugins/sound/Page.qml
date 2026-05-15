import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#121212"

    required property var api
    required property string pluginId
    required property string pluginName
    required property url pluginDir

    property var sinks: []
    property var sources: []
    property var cards: []
    property string defaultSinkName: ""
    property string defaultSourceName: ""
    property string errorText: ""

    // Orbital runs as root, but pipewire-pulse runs in a user session and
    // refuses connections from other uids even if XDG_RUNTIME_DIR is set.
    // We detect the user that owns /run/user/<uid>/pulse/native and run
    // every audio command via `runuser -u <user> -- env XDG_RUNTIME_DIR=...`
    // so the subprocess actually matches that user.
    property string audioUid: ""
    property string audioUser: ""
    property bool runtimeReady: false

    readonly property var currentSink: pickByName(sinks, defaultSinkName)
    readonly property var currentSource: pickByName(filteredSources(), defaultSourceName)

    function pickByName(list, name) {
        for (var i = 0; i < list.length; ++i) {
            if (list[i].name === name) return list[i]
        }
        return list.length > 0 ? list[0] : null
    }

    function filteredSources() {
        var out = []
        for (var i = 0; i < sources.length; ++i) {
            var s = sources[i]
            if (s.name && s.name.indexOf(".monitor") < 0) out.push(s)
        }
        return out
    }

    function parsePercent(p) {
        if (p === undefined || p === null) return 0
        return parseInt(String(p).replace("%", "").trim()) || 0
    }

    function channelNames(device) {
        if (!device || !device.channel_map) return []
        return String(device.channel_map).split(",").map(function(s) { return s.trim() }).filter(Boolean)
    }

    function channelPercent(device, ch) {
        if (!device || !device.volume || !device.volume[ch]) return 0
        return parsePercent(device.volume[ch].value_percent)
    }

    function averagePercent(device) {
        var chs = channelNames(device)
        if (chs.length === 0) return 0
        var sum = 0
        for (var i = 0; i < chs.length; ++i) sum += channelPercent(device, chs[i])
        return Math.round(sum / chs.length)
    }

    // --- runtime + command wrapping ---

    function detectRuntime() {
        var probe =
            'for d in /run/user/*; do\n' +
            '  uid=$(basename "$d")\n' +
            '  [ "$uid" = "0" ] && continue\n' +
            '  if [ -S "$d/pulse/native" ]; then\n' +
            '    user=$(id -nu "$uid" 2>/dev/null)\n' +
            '    [ -n "$user" ] && echo "$uid:$user" && exit 0\n' +
            '  fi\n' +
            'done\n' +
            'if [ -S /run/user/0/pulse/native ]; then echo "0:root"; exit 0; fi\n' +
            'exit 1'
        api.run("sh", ["-c", probe], function(code, out, err) {
            if (code === 0) {
                var parts = out.trim().split(":")
                root.audioUid = parts[0]
                root.audioUser = parts[1]
            } else {
                root.errorText = "No PipeWire/PulseAudio user session found under /run/user/*"
            }
            root.runtimeReady = true
            root.refreshAll()
        })
    }

    function audioRun(prog, args, cb) {
        if (root.audioUser && root.audioUid) {
            var wrapped = ["-u", root.audioUser, "--",
                           "env", "XDG_RUNTIME_DIR=/run/user/" + root.audioUid,
                           prog].concat(args)
            api.run("runuser", wrapped, cb)
        } else {
            api.run(prog, args, cb)
        }
    }

    // --- pactl interactions ---

    function refreshAll() {
        refreshList("sinks")
        refreshList("sources")
        refreshList("cards")
        refreshDefault("sink")
        refreshDefault("source")
    }

    function refreshList(kind) {
        audioRun("pactl", ["-f", "json", "list", kind], function(code, out, err) {
            if (code !== 0) {
                root.errorText = "pactl unavailable: " + (err || "exit " + code)
                return
            }
            root.errorText = ""
            try {
                var parsed = JSON.parse(out)
                if (kind === "sinks") root.sinks = parsed
                else if (kind === "sources") root.sources = parsed
                else if (kind === "cards") root.cards = parsed
            } catch (e) {
                root.errorText = "Failed to parse pactl output"
            }
        })
    }

    function cardDisplayName(card) {
        if (!card) return ""
        var p = card.properties || {}
        return p["device.description"] || p["alsa.card_name"] || p["device.product.name"] || card.name
    }

    function cardActiveProfileDescription(card) {
        if (!card || !card.profiles) return ""
        var active = card.active_profile
        if (active && card.profiles[active] && card.profiles[active].description) {
            return card.profiles[active].description
        }
        return active || "(no profile)"
    }

    function openCardProfile(card) {
        api.pushPage(Qt.resolvedUrl("CardProfilePage.qml"), {
            "api": root.api,
            "pluginId": root.pluginId,
            "cardName": card.name,
            "cardDisplay": cardDisplayName(card),
            "audioUid": root.audioUid,
            "audioUser": root.audioUser
        })
    }

    function refreshDefault(kind) {
        audioRun("pactl", ["get-default-" + kind], function(code, out) {
            if (code !== 0) return
            if (kind === "sink") root.defaultSinkName = out.trim()
            else root.defaultSourceName = out.trim()
        })
    }

    function setSinkUniform(percent) {
        if (!currentSink) return
        audioRun("pactl",["set-sink-volume", currentSink.name, percent + "%"], function() {})
    }

    function setSinkChannel(channelIndex, percent) {
        if (!currentSink) return
        var chs = channelNames(currentSink)
        var vals = []
        for (var i = 0; i < chs.length; ++i) {
            vals.push((i === channelIndex ? percent : channelPercent(currentSink, chs[i])) + "%")
        }
        var args = ["set-sink-volume", currentSink.name].concat(vals)
        audioRun("pactl",args, function() {})
    }

    function setSinkMute(muted) {
        if (!currentSink) return
        audioRun("pactl",["set-sink-mute", currentSink.name, muted ? "1" : "0"], function() {})
    }

    function setSourceUniform(percent) {
        if (!currentSource) return
        audioRun("pactl",["set-source-volume", currentSource.name, percent + "%"], function() {})
    }

    function setSourceChannel(channelIndex, percent) {
        if (!currentSource) return
        var chs = channelNames(currentSource)
        var vals = []
        for (var i = 0; i < chs.length; ++i) {
            vals.push((i === channelIndex ? percent : channelPercent(currentSource, chs[i])) + "%")
        }
        var args = ["set-source-volume", currentSource.name].concat(vals)
        audioRun("pactl",args, function() {})
    }

    function setSourceMute(muted) {
        if (!currentSource) return
        audioRun("pactl",["set-source-mute", currentSource.name, muted ? "1" : "0"], function() {})
    }

    function testOutput() {
        if (!currentSink) return
        audioRun("paplay", ["--device=" + currentSink.name, "/usr/share/sounds/alsa/Front_Center.wav"], function(code, out, err) {
            if (code !== 0) api.toast("Test sound failed: " + (err || "exit " + code).split("\n")[0])
        })
    }

    function testInput() {
        if (!currentSource) return
        api.toast("Recording 3 seconds…")
        var raw = "/tmp/orbital-input-test.raw"
        var cmd = "timeout 3 parec --device='" + currentSource.name +
                  "' --rate=44100 --channels=1 --format=s16le --raw > " + raw +
                  " && paplay --rate=44100 --channels=1 --format=s16le --raw " + raw
        audioRun("sh", ["-c", cmd], function(code, out, err) {
            if (code !== 0 && code !== 124) {
                api.toast("Test failed: " + (err || "exit " + code).split("\n")[0])
            } else {
                api.toast("Playback complete")
            }
        })
    }

    function openPicker(kind) {
        api.pushPage(Qt.resolvedUrl("DeviceListPage.qml"), {
            "api": root.api,
            "pluginId": root.pluginId,
            "kind": kind,
            "title": kind === "sink" ? "Output Device" : "Input Device",
            "currentName": kind === "sink" ? root.defaultSinkName : root.defaultSourceName,
            "audioUid": root.audioUid,
            "audioUser": root.audioUser
        })
    }

    Component.onCompleted: detectRuntime()

    Timer {
        interval: 2000
        running: root.runtimeReady
        repeat: true
        onTriggered: root.refreshAll()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- header ---
        Rectangle {
            Layout.fillWidth: true
            height: 52
            color: "#1e1e1e"

            RowLayout {
                anchors.fill: parent
                spacing: 0
                anchors.leftMargin: 10
                anchors.rightMargin: 15

                ToolButton {
                    Layout.preferredWidth: 52
                    Layout.fillHeight: true

                    contentItem: IconImage {
                        anchors.centerIn: parent
                        source: "qrc:/MyDesktop/Backend/assets/back.svg"
                        sourceSize: Qt.size(48, 48)
                        color: "white"
                    }

                    background: Rectangle {
                        color: parent.pressed ? "#333" : "transparent"
                    }

                    onClicked: stackView.pop()
                }

                Text {
                    text: root.pluginName
                    color: "white"
                    font.bold: true
                    font.pixelSize: 25
                    Layout.leftMargin: 5
                }

                Item { Layout.fillWidth: true }
            }
        }

        // --- error banner ---
        Rectangle {
            Layout.fillWidth: true
            visible: root.errorText !== ""
            color: "#3a1f1f"
            implicitHeight: errLabel.implicitHeight + 18
            Text {
                id: errLabel
                anchors.fill: parent
                anchors.margins: 9
                text: root.errorText
                color: "#ff8a80"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        // --- content ---
        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: scroll.availableWidth
                spacing: 20

                Item { height: 6 }

                DeviceSection {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20

                    label: "Output"
                    device: root.currentSink
                    onPickRequested: root.openPicker("sink")
                    onMasterCommit: function(value) { root.setSinkUniform(value) }
                    onChannelCommit: function(index, value) { root.setSinkChannel(index, value) }
                    onMuteToggled: function(muted) { root.setSinkMute(muted) }
                    onTestRequested: root.testOutput()

                    parsePercent: root.parsePercent
                    channelNames: root.channelNames
                    channelPercent: root.channelPercent
                    averagePercent: root.averagePercent
                }

                DeviceSection {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20

                    label: "Input"
                    device: root.currentSource
                    onPickRequested: root.openPicker("source")
                    onMasterCommit: function(value) { root.setSourceUniform(value) }
                    onChannelCommit: function(index, value) { root.setSourceChannel(index, value) }
                    onMuteToggled: function(muted) { root.setSourceMute(muted) }
                    onTestRequested: root.testInput()
                    testButtonText: "Record + Play"

                    parsePercent: root.parsePercent
                    channelNames: root.channelNames
                    channelPercent: root.channelPercent
                    averagePercent: root.averagePercent
                }

                // --- Cards section ---
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    color: "#1e1e1e"
                    radius: 12
                    implicitHeight: cardCol.implicitHeight + 30

                    ColumnLayout {
                        id: cardCol
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 10

                        Text {
                            text: "Cards"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Repeater {
                            model: root.cards

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 56
                                color: cardTap.pressed ? "#333" : "#2a2a2a"
                                radius: 8

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 8

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: root.cardDisplayName(modelData)
                                            color: "white"
                                            font.pixelSize: 13
                                            font.bold: true
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: root.cardActiveProfileDescription(modelData)
                                            color: "#888"
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Text { text: "›"; color: "#666"; font.pixelSize: 18 }
                                }

                                TapHandler {
                                    id: cardTap
                                    onTapped: root.openCardProfile(modelData)
                                }
                            }
                        }

                        Text {
                            text: "No sound cards found."
                            color: "#666"
                            font.pixelSize: 12
                            Layout.alignment: Qt.AlignHCenter
                            visible: root.cards.length === 0
                        }
                    }
                }

                Item { height: 20 }
            }
        }
    }

    // --- inline component for a device section card ---
    component DeviceSection : Rectangle {
        id: section

        property string label: ""
        property var device: null
        property string testButtonText: "Test"

        property var parsePercent
        property var channelNames
        property var channelPercent
        property var averagePercent

        signal pickRequested()
        signal masterCommit(int value)
        signal channelCommit(int index, int value)
        signal muteToggled(bool muted)
        signal testRequested()

        implicitHeight: inner.implicitHeight + 30
        color: "#1e1e1e"
        radius: 12

        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 15
            spacing: 12

            Text {
                text: section.label
                color: "white"
                font.pixelSize: 16
                font.bold: true
            }

            // Device row
            Rectangle {
                Layout.fillWidth: true
                height: 44
                radius: 8
                color: devTap.pressed ? "#333" : "#2a2a2a"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Text {
                        text: "Device"
                        color: "#aaa"
                        font.pixelSize: 12
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: section.device ? (section.device.description || section.device.name) : "(none)"
                        color: "white"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }

                    Text { text: "›"; color: "#666"; font.pixelSize: 18 }
                }

                TapHandler {
                    id: devTap
                    onTapped: section.pickRequested()
                }
            }

            // Master + per-channel sliders + actions
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: section.device !== null && section.device !== undefined

                VolumeSlider {
                    label: "Master"
                    Layout.fillWidth: true
                    targetValue: section.device ? section.averagePercent(section.device) : 0
                    onCommit: function(v) { section.masterCommit(v) }
                }

                Repeater {
                    model: section.device ? section.channelNames(section.device) : []

                    delegate: VolumeSlider {
                        Layout.fillWidth: true
                        label: modelData
                        targetValue: section.device ? section.channelPercent(section.device, modelData) : 0
                        onCommit: function(v) { section.channelCommit(index, v) }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8

                    ActionChip {
                        text: section.device && section.device.mute ? "Unmute" : "Mute"
                        active: section.device && section.device.mute
                        onTapped: section.muteToggled(!(section.device && section.device.mute))
                    }

                    ActionChip {
                        text: section.testButtonText
                        onTapped: section.testRequested()
                    }
                }
            }

            Text {
                text: "No device available."
                color: "#666"
                font.pixelSize: 12
                Layout.alignment: Qt.AlignHCenter
                visible: !section.device
            }
        }
    }

    // --- inline component for a pill button (matches LED page style) ---
    component ActionChip : Rectangle {
        id: chip
        property alias text: chipText.text
        property bool active: false
        signal tapped()

        implicitWidth: 104
        implicitHeight: 36
        radius: 17
        color: active ? "#0079DB" : (chipTap.pressed ? "#2a2a2a" : "#1e1e1e")
        border.color: active ? "#38A7FF" : "#3d3d3d"
        border.width: 1

        Text {
            id: chipText
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 12
            font.bold: false
            width: parent.width - 20
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        TapHandler {
            id: chipTap
            onTapped: chip.tapped()
        }
    }

    // --- inline component for a labeled volume slider ---
    component VolumeSlider : ColumnLayout {
        id: vs

        property string label: ""
        property int targetValue: 0

        signal commit(int value)

        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: vs.label
                color: "#aaa"
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                text: slider.value.toFixed(0) + "%"
                color: "#aaa"
                font.pixelSize: 12
                font.family: "Monospace"
            }
        }

        Slider {
            id: slider
            Layout.fillWidth: true
            from: 0; to: 100; stepSize: 1
            value: vs.targetValue

            Binding on value {
                value: vs.targetValue
                when: !slider.pressed
            }

            onPressedChanged: {
                if (!pressed) vs.commit(Math.round(value))
            }

            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                implicitWidth: 200
                implicitHeight: 4
                width: slider.availableWidth
                height: implicitHeight
                radius: 2
                color: "#333"
                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    color: "#0079DB"
                    radius: 2
                }
            }

            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                implicitWidth: 20
                implicitHeight: 20
                radius: 10
                color: slider.pressed ? "#f0f0f0" : "#ffffff"
                border.color: "#0079DB"
            }
        }
    }
}
