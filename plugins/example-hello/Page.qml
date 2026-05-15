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

    property string uptimeText: ""

    function refreshUptime() {
        root.api.run("cat", ["/proc/uptime"], function(code, out, err) {
            if (code === 0) {
                root.uptimeText = out.trim()
            } else {
                root.uptimeText = "error: " + err.trim()
            }
        })
    }

    Component.onCompleted: refreshUptime()

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

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 16

                Text {
                    text: "Hello from " + root.pluginId
                    color: "white"
                    font.pixelSize: 20
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "/proc/uptime: " + (root.uptimeText || "(loading)")
                    color: "#aaa"
                    font.pixelSize: 12
                    font.family: "Monospace"
                    wrapMode: Text.WrapAnywhere
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12

                    Button {
                        text: "Refresh"
                        onClicked: root.refreshUptime()
                    }

                    Button {
                        text: "Toast"
                        onClicked: root.api.toast("Hello from " + root.pluginName + "!")
                    }
                }
            }
        }
    }
}
