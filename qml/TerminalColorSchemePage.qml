import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#121212"

    required property var terminalBackend

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
                    text: "Color Scheme"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 25
                    Layout.leftMargin: 5
                }

                Item { Layout.fillWidth: true }
            }
        }

        ScrollView {
            id: schemeScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: schemeScroll.availableWidth
                spacing: 12

                Item { height: 8 }

                Repeater {
                    model: root.terminalBackend ? root.terminalBackend.colorSchemeList : []

                    Rectangle {
                        id: schemeCard
                        Layout.fillWidth: true
                        Layout.leftMargin: 20
                        Layout.rightMargin: 20
                        height: previewCol.implicitHeight + 28
                        radius: 12

                        readonly property bool isActive: modelData === root.terminalBackend.colorScheme
                        readonly property var colors: root.terminalBackend.colorSchemeColors(modelData)

                        color: isActive ? "#1a2a3a" : (schemeTap.pressed ? "#2a2a2a" : "#1e1e1e")
                        border.width: isActive ? 1 : 0
                        border.color: "#4080C0"

                        ColumnLayout {
                            id: previewCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: modelData
                                    color: "white"
                                    font.pixelSize: 16
                                    font.bold: true
                                    Layout.fillWidth: true
                                }

                                Text {
                                    visible: schemeCard.isActive
                                    text: "Active"
                                    color: "#4080C0"
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }

                            // Normal colors row (0-7)
                            Row {
                                spacing: 4

                                Repeater {
                                    model: 8

                                    Rectangle {
                                        width: 28
                                        height: 18
                                        radius: 3
                                        color: schemeCard.colors.length > index ? schemeCard.colors[index] : "gray"
                                    }
                                }
                            }

                            // Bright colors row (8-15)
                            Row {
                                spacing: 4

                                Repeater {
                                    model: 8

                                    Rectangle {
                                        width: 28
                                        height: 18
                                        radius: 3
                                        color: schemeCard.colors.length > (index + 8) ? schemeCard.colors[index + 8] : "gray"
                                    }
                                }
                            }
                        }

                        TapHandler {
                            id: schemeTap
                            onTapped: root.terminalBackend.colorScheme = modelData
                        }
                    }
                }

                Item { height: 20 }
            }
        }
    }
}
