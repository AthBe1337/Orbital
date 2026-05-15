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

    property string lastGreet: api.settingValue("lastGreet", "(never)")

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
                    text: "Greetings — and thanks to example-hello"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                Text {
                    text: "Last greet recorded: " + root.lastGreet
                    color: "#888"
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignHCenter
                }

                Button {
                    text: "Greet"
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: {
                        var now = new Date().toISOString()
                        root.api.setSettingValue("lastGreet", now)
                        root.lastGreet = now
                        root.api.toast("Hi there!")
                    }
                }
            }
        }
    }
}
