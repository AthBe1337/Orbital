import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#121212"

    required property var backend
    property var pluginManager: root.backend ? root.backend.pluginManager : null

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
                    text: "Plugins"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 25
                    Layout.leftMargin: 5
                }

                Item { Layout.fillWidth: true }
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
            model: root.pluginManager ? root.pluginManager.plugins : []

            delegate: Rectangle {
                width: ListView.view.width - 40
                x: 20
                height: 70
                color: tapRow.pressed ? "#2a2a2a" : "#1e1e1e"
                radius: 12

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 12

                    IconImage {
                        source: modelData.iconUrl && modelData.iconUrl.toString() !== ""
                                ? modelData.iconUrl
                                : "qrc:/MyDesktop/Backend/assets/plug.svg"
                        sourceSize: Qt.size(28, 28)
                        color: "white"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: modelData.name
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: modelData.description
                            color: "#888"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Text {
                        text: "›"
                        color: "#666"
                        font.pixelSize: 22
                    }
                }

                TapHandler {
                    id: tapRow
                    onTapped: {
                        stackView.push(modelData.pageUrl, {
                            "pluginId": modelData.id,
                            "pluginName": modelData.name
                        })
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: "No plugins installed."
                color: "#666"
                font.pixelSize: 14
            }
        }
    }
}
