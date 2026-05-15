import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#121212"

    required property var api
    required property string pluginId
    required property string cardName
    required property string cardDisplay
    required property string audioUid
    required property string audioUser

    property var profiles: []   // [{name, description, available, priority}, ...]
    property string activeName: ""
    property string errorText: ""

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

    function refresh() {
        audioRun("pactl", ["-f", "json", "list", "cards"], function(code, out, err) {
            if (code !== 0) {
                root.errorText = "pactl error: " + (err || "exit " + code)
                return
            }
            try {
                var cards = JSON.parse(out)
                for (var i = 0; i < cards.length; ++i) {
                    if (cards[i].name === root.cardName) {
                        var profMap = cards[i].profiles || {}
                        var arr = []
                        for (var key in profMap) {
                            var p = profMap[key] || {}
                            arr.push({
                                name: key,
                                description: p.description || key,
                                available: p.available !== "no",
                                priority: p.priority || 0
                            })
                        }
                        arr.sort(function(a, b) { return b.priority - a.priority })
                        root.profiles = arr
                        root.activeName = cards[i].active_profile || ""
                        root.errorText = ""
                        return
                    }
                }
                root.errorText = "Card not found: " + root.cardName
            } catch (e) {
                root.errorText = "Failed to parse pactl output"
            }
        })
    }

    function selectProfile(name) {
        audioRun("pactl", ["set-card-profile", root.cardName, name], function(code, out, err) {
            if (code !== 0) {
                api.toast("Set profile failed: " + (err || "exit " + code).split("\n")[0])
                return
            }
            stackView.pop()
        })
    }

    Component.onCompleted: refresh()

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

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 5
                    spacing: 0

                    Text {
                        text: "Card Profile"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 20
                    }

                    Text {
                        text: root.cardDisplay
                        color: "#888"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
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

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            spacing: 10
            clip: true
            model: root.profiles

            delegate: Rectangle {
                width: ListView.view.width - 40
                x: 20
                height: 64
                color: tapRow.pressed ? "#2a2a2a" : "#1e1e1e"
                radius: 12
                opacity: modelData.available ? 1.0 : 0.5

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 15
                    anchors.rightMargin: 15
                    spacing: 12

                    Rectangle {
                        width: 18; height: 18
                        radius: 9
                        color: "transparent"
                        border.color: modelData.name === root.activeName ? "#0079DB" : "#666"
                        border.width: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: 10; height: 10
                            radius: 5
                            color: "#0079DB"
                            visible: modelData.name === root.activeName
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: modelData.description
                            color: "white"
                            font.pixelSize: 14
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: modelData.name + (modelData.available ? "" : "  •  unavailable")
                            color: "#666"
                            font.pixelSize: 10
                            font.family: "Monospace"
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }
                }

                TapHandler {
                    id: tapRow
                    enabled: modelData.available
                    onTapped: root.selectProfile(modelData.name)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0 && root.errorText === ""
                text: "No profiles available."
                color: "#666"
                font.pixelSize: 14
            }
        }
    }
}
