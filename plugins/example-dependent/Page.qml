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

                Rectangle {
                    Layout.preferredWidth: 64
                    Layout.fillHeight: true
                    radius: 8
                    color: backTap.pressed ? "#333" : "transparent"
                    IconImage {
                        anchors.centerIn: parent
                        source: "qrc:/MyDesktop/Backend/assets/back.svg"
                        sourceSize: Qt.size(48, 48)
                        color: "white"
                    }
                    TapHandler {
                        id: backTap
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: stackView.pop()
                    }
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

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 120; implicitHeight: 44
                    radius: 8
                    color: tapGreet.pressed ? "#3a3a3a" : "#252525"
                    border.color: "#555"
                    Text {
                        anchors.centerIn: parent
                        text: "Greet"
                        color: "white"
                    }
                    TapHandler {
                        id: tapGreet
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: {
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
}
