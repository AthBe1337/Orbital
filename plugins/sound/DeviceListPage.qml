import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#121212"

    required property var api
    required property string pluginId
    required property string kind         // "sink" or "source"
    required property string title
    required property string currentName
    required property string audioUid
    required property string audioUser

    property var devices: []
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
        audioRun("pactl", ["-f", "json", "list", root.kind + "s"], function(code, out, err) {
            if (code !== 0) {
                root.errorText = "pactl error: " + (err || "exit " + code)
                return
            }
            try {
                var parsed = JSON.parse(out)
                if (root.kind === "source") {
                    root.devices = parsed.filter(function(d) { return d.name && d.name.indexOf(".monitor") < 0 })
                } else {
                    root.devices = parsed
                }
                root.errorText = ""
            } catch (e) {
                root.errorText = "Failed to parse pactl output"
            }
        })
    }

    function select(name) {
        audioRun("pactl", ["set-default-" + root.kind, name], function() {
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

                Text {
                    text: root.title
                    color: "white"
                    font.bold: true
                    font.pixelSize: 22
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

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            spacing: 10
            clip: true
            model: root.devices

            delegate: Rectangle {
                width: ListView.view.width - 40
                x: 20
                height: descTxt.visible ? 64 : 48
                color: tapRow.pressed ? "#2a2a2a" : "#1e1e1e"
                radius: 12

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 15
                    anchors.rightMargin: 15
                    spacing: 12

                    Rectangle {
                        width: 18; height: 18
                        radius: 9
                        color: "transparent"
                        border.color: modelData.name === root.currentName ? "#0079DB" : "#666"
                        border.width: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: 10; height: 10
                            radius: 5
                            color: "#0079DB"
                            visible: modelData.name === root.currentName
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: modelData.description || modelData.name
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            id: descTxt
                            text: modelData.name
                            color: "#666"
                            font.pixelSize: 10
                            font.family: "Monospace"
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                            visible: modelData.description && modelData.description !== modelData.name
                        }
                    }
                }

                TapHandler {
                    id: tapRow
                    onTapped: root.select(modelData.name)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0 && root.errorText === ""
                text: root.kind === "sink" ? "No outputs found." : "No inputs found."
                color: "#666"
                font.pixelSize: 14
            }
        }
    }
}
