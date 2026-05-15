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

    property bool powered: false
    property bool scanning: false
    property var devices: []
    property bool hideUnnamed: false
    property string errorText: ""

    readonly property var visibleDevices: {
        if (!root.hideUnnamed) return root.devices
        var out = []
        for (var i = 0; i < root.devices.length; ++i) {
            if (!root.isUnnamed(root.devices[i])) out.push(root.devices[i])
        }
        return out
    }
    readonly property int hiddenCount: root.devices.length - root.visibleDevices.length

    readonly property string statusScript:
        'echo "===POWER==="\n' +
        'bluetoothctl show 2>/dev/null | sed -n "s/^[[:space:]]*Powered:[[:space:]]*\\(.*\\)/\\1/p"\n' +
        'echo "===PAIRED==="\n' +
        'bluetoothctl devices Paired 2>/dev/null\n' +
        'echo "===CONNECTED==="\n' +
        'bluetoothctl devices Connected 2>/dev/null\n' +
        'echo "===ALL==="\n' +
        'bluetoothctl devices 2>/dev/null\n'

    function parseDeviceLines(text) {
        var out = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; ++i) {
            var m = lines[i].match(/^Device\s+([0-9A-Fa-f:]{17})(?:\s+(.*))?$/)
            if (m) out.push({ mac: m[1], name: (m[2] || "").trim() })
        }
        return out
    }

    function isUnnamed(d) {
        if (!d || !d.name) return true
        var n = d.name.trim()
        if (!n) return true
        var hex = n.replace(/[-:]/g, "").toUpperCase()
        var macHex = d.mac.replace(/[-:]/g, "").toUpperCase()
        return hex === macHex
    }

    function setHideUnnamed(v) {
        root.hideUnnamed = v
        api.setSettingValue("hideUnnamed", v)
    }

    function refresh() {
        api.run("sh", ["-c", root.statusScript], function(code, out, err) {
            if (code !== 0) {
                root.errorText = "bluetoothctl unavailable: " + (err || "exit " + code).split("\n")[0]
                return
            }
            root.errorText = ""

            var sections = { POWER: "", PAIRED: "", CONNECTED: "", ALL: "" }
            var current = null
            var lines = out.split("\n")
            for (var i = 0; i < lines.length; ++i) {
                var hdr = lines[i].match(/^===(\w+)===$/)
                if (hdr) { current = hdr[1]; continue }
                if (current) sections[current] += lines[i] + "\n"
            }

            root.powered = sections.POWER.trim() === "yes"

            var pairedList = parseDeviceLines(sections.PAIRED)
            var connectedList = parseDeviceLines(sections.CONNECTED)
            var allList = parseDeviceLines(sections.ALL)

            var pairedMacs = {}
            for (var p = 0; p < pairedList.length; ++p) pairedMacs[pairedList[p].mac] = true
            var connectedMacs = {}
            for (var c = 0; c < connectedList.length; ++c) connectedMacs[connectedList[c].mac] = true

            var byMac = {}
            function ingest(list) {
                for (var i = 0; i < list.length; ++i) {
                    var d = list[i]
                    if (!byMac[d.mac]) {
                        byMac[d.mac] = {
                            mac: d.mac,
                            name: d.name || d.mac,
                            paired: !!pairedMacs[d.mac],
                            connected: !!connectedMacs[d.mac]
                        }
                    } else if (!byMac[d.mac].name && d.name) {
                        byMac[d.mac].name = d.name
                    }
                }
            }
            ingest(allList)
            ingest(pairedList)
            ingest(connectedList)

            var merged = []
            for (var mac in byMac) merged.push(byMac[mac])
            merged.sort(function(a, b) {
                if (a.connected !== b.connected) return a.connected ? -1 : 1
                if (a.paired !== b.paired) return a.paired ? -1 : 1
                return a.name.localeCompare(b.name)
            })
            root.devices = merged
        })
    }

    function setPower(on) {
        api.run("bluetoothctl", ["power", on ? "on" : "off"], function(code, out, err) {
            if (code !== 0) api.toast("Power change failed: " + (err || out || "exit " + code).split("\n")[0])
            root.refresh()
        })
    }

    function startScan(silent) {
        if (root.scanning) return
        if (!root.powered) {
            if (!silent) api.toast("Bluetooth is off")
            return
        }
        root.scanning = true
        api.run("bluetoothctl", ["--timeout", "8", "scan", "on"], function(code, out, err) {
            root.scanning = false
            if (code !== 0 && !silent) {
                var msg = (err || out || "exit " + code).split("\n")[0]
                if (msg) api.toast("Scan failed: " + msg)
            }
            root.refresh()
            if (root.powered) autoScanTimer.restart()
        })
    }

    onPoweredChanged: {
        if (root.powered && !root.scanning) autoScanTimer.restart()
        else if (!root.powered) autoScanTimer.stop()
    }

    Timer {
        id: autoScanTimer
        interval: 3000
        repeat: false
        onTriggered: root.startScan(true)
    }

    function openDevice(d) {
        api.pushPage(Qt.resolvedUrl("DeviceDetailPage.qml"), {
            "api": root.api,
            "pluginId": root.pluginId,
            "mac": d.mac,
            "deviceName": d.name
        })
    }

    Component.onCompleted: {
        root.hideUnnamed = api.settingValue("hideUnnamed", false) === true
        root.refresh()
    }

    Timer {
        interval: 2500
        running: true
        repeat: true
        onTriggered: if (!root.scanning) root.refresh()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

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

        Rectangle {
            Layout.fillWidth: true
            height: 72
            color: "#121212"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20

                Text {
                    text: "Enable Bluetooth"
                    color: "white"
                    font.pixelSize: 18
                }

                Item { Layout.fillWidth: true }

                ToggleSwitch {
                    checked: root.powered
                    onToggled: function(requested) { root.setPower(requested) }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: scroll.availableWidth
                spacing: 20

                Item { height: 14 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    color: "#1e1e1e"
                    radius: 12
                    implicitHeight: devicesCol.implicitHeight + 30

                    ColumnLayout {
                        id: devicesCol
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Devices"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                            }

                            Item { Layout.fillWidth: true }

                            ActionChip {
                                text: root.scanning ? "Scanning…" : "Scan"
                                active: root.scanning
                                enabled: root.powered && !root.scanning
                                onTapped: root.startScan()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Hide unnamed"
                                color: "#aaa"
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }

                            ToggleSwitch {
                                checked: root.hideUnnamed
                                onToggled: function(requested) { root.setHideUnnamed(requested) }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            Layout.bottomMargin: 2
                            implicitHeight: 1
                            color: "#2a2a2a"
                        }

                        Repeater {
                            model: root.visibleDevices

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 56
                                color: devTap.pressed ? "#333" : "#2a2a2a"
                                radius: 8

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    Rectangle {
                                        width: 10; height: 10
                                        radius: 5
                                        color: modelData.connected
                                               ? "#4caf50"
                                               : (modelData.paired ? "#0079DB" : "#555")
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: modelData.name
                                            color: "white"
                                            font.pixelSize: 13
                                            font.bold: true
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: {
                                                var bits = []
                                                if (modelData.connected) bits.push("Connected")
                                                else if (modelData.paired) bits.push("Paired")
                                                else bits.push("Available")
                                                bits.push(modelData.mac)
                                                return bits.join("  •  ")
                                            }
                                            color: "#888"
                                            font.pixelSize: 11
                                            font.family: "Monospace"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Text { text: "›"; color: "#666"; font.pixelSize: 18 }
                                }

                                TapHandler {
                                    id: devTap
                                    onTapped: root.openDevice(modelData)
                                }
                            }
                        }

                        Text {
                            text: {
                                if (root.devices.length === 0) {
                                    return root.powered
                                           ? "No devices yet. Tap Scan to discover."
                                           : "Turn Bluetooth on to see devices."
                                }
                                return root.hiddenCount === 1
                                       ? "1 unnamed device hidden by filter."
                                       : root.hiddenCount + " unnamed devices hidden by filter."
                            }
                            color: "#666"
                            font.pixelSize: 12
                            Layout.alignment: Qt.AlignHCenter
                            visible: root.visibleDevices.length === 0
                        }
                    }
                }

                Item { height: 20 }
            }
        }
    }

    component ToggleSwitch : Item {
        id: sw
        property bool checked: false
        property bool enabled: true
        signal toggled(bool requested)

        implicitWidth: 46
        implicitHeight: 26
        opacity: sw.enabled ? 1.0 : 0.45

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: sw.checked ? "#0079DB" : "#3d3d3d"
            border.color: sw.checked ? "#38A7FF" : "#555"
            border.width: 1
            Behavior on color { ColorAnimation { duration: 150 } }

            Rectangle {
                id: thumb
                width: parent.height - 6
                height: parent.height - 6
                radius: width / 2
                color: "white"
                y: 3
                x: sw.checked ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }
        }

        TapHandler {
            enabled: sw.enabled
            onTapped: sw.toggled(!sw.checked)
        }
    }

    component ActionChip : Rectangle {
        id: chip
        property alias text: chipText.text
        property bool active: false
        property bool enabled: true
        signal tapped()

        implicitWidth: 104
        implicitHeight: 36
        radius: 17
        opacity: chip.enabled ? 1.0 : 0.45
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
            enabled: chip.enabled
            onTapped: chip.tapped()
        }
    }
}
