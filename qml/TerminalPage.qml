import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import MyDesktop.Backend 1.0

Page {
    id: terminalPage
    background: Rectangle { color: "#121212" }

    required property var terminalBackend

    property bool keyboardVisible: true
    property string toastMessage: ""

    function showToast(message) {
        toastMessage = message
        toastTimer.restart()
    }

    function adjustFontSize(delta) {
        var nextSize = terminalBackend.fontPixelSize + delta
        if (nextSize === terminalBackend.fontPixelSize)
            return
        terminalBackend.fontPixelSize = nextSize
        showToast("Font " + terminalBackend.fontPixelSize + " px")
    }

    component TerminalPillButton : Rectangle {
        id: control

        property string text: ""
        property color accentColor: "#88C0D0"
        property bool active: false
        property bool prominent: false
        property bool compact: true
        property bool enabled: true
        readonly property bool pressed: buttonArea.pressed

        signal clicked()

        implicitHeight: compact ? 32 : 38
        implicitWidth: Math.max(compact ? 58 : 86, label.implicitWidth + (compact ? 22 : 28))
        radius: control.compact ? 10 : 12
        border.width: 1
        border.color: !control.enabled ? "#262D38"
                                       : control.prominent ? control.accentColor
                                                           : control.active ? Qt.lighter(control.accentColor, 1.1)
                                                                            : control.pressed ? "#455266"
                                                                                              : "#2F3847"
        color: !control.enabled ? "#151920"
                                : control.prominent ? "#233547"
                                                    : control.active ? "#203546"
                                                                     : control.pressed ? "#222B36"
                                                                                       : "#181D25"

        Text {
            id: label
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            anchors.fill: parent
            text: control.text
            color: !control.enabled ? "#5B6576" : (control.prominent || control.active ? "#F4F8FB" : "#D8DEE9")
            font.pixelSize: control.compact ? 12 : 13
            font.bold: true
        }

        TapHandler {
            id: buttonArea
            enabled: control.enabled
            gesturePolicy: TapHandler.DragThreshold
            onTapped: control.clicked()
        }
    }

    component TerminalBadge : Rectangle {
        id: badge

        property string label: ""

        implicitHeight: 32
        implicitWidth: badgeText.implicitWidth + 22
        radius: 10
        color: "#131821"
        border.width: 1
        border.color: "#2F3847"

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: badge.label
            color: "#AAB6C5"
            font.pixelSize: 12
            font.bold: true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.bottomMargin: keyboardVisible ? terminalKeyboard.height : 0
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            height: 68
            color: "#1a1f29"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 12
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 52
                    Layout.fillHeight: true
                    radius: 10
                    color: backButtonArea.pressed ? "#2B3340" : "transparent"

                    IconImage {
                        anchors.centerIn: parent
                        source: "qrc:/MyDesktop/Backend/assets/back.svg"
                        sourceSize: Qt.size(48, 48)
                        color: "white"
                    }

                    TapHandler {
                        id: backButtonArea
                        gesturePolicy: TapHandler.DragThreshold
                        onTapped: stackView.pop()
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        text: "Terminal"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 21
                        elide: Text.ElideRight
                    }

                    Text {
                        text: terminalPage.terminalBackend.title || "Shell"
                        color: "#93A1B3"
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }

                TerminalPillButton {
                    text: keyboardVisible ? "Hide KB" : "Keyboard"
                    compact: true
                    active: keyboardVisible
                    accentColor: "#81A1C1"
                    onClicked: keyboardVisible = !keyboardVisible
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 56
            color: "#141821"

            Flickable {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                contentWidth: actionRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: actionRow
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter

                    TerminalPillButton {
                        text: "A-"
                        enabled: terminalPage.terminalBackend.fontPixelSize > terminalPage.terminalBackend.minFontPixelSize
                        onClicked: terminalPage.adjustFontSize(-1)
                    }

                    TerminalBadge {
                        label: terminalPage.terminalBackend.fontPixelSize + " px"
                    }

                    TerminalPillButton {
                        text: "A+"
                        enabled: terminalPage.terminalBackend.fontPixelSize < terminalPage.terminalBackend.maxFontPixelSize
                        onClicked: terminalPage.adjustFontSize(1)
                    }

                    TerminalPillButton { text: "Ctrl+C"; onClicked: terminalPage.terminalBackend.sendKey(Qt.Key_C, Qt.ControlModifier) }
                    TerminalPillButton { text: "Ctrl+D"; onClicked: terminalPage.terminalBackend.sendKey(Qt.Key_D, Qt.ControlModifier) }
                    TerminalPillButton { text: "Ctrl+L"; onClicked: terminalPage.terminalBackend.sendKey(Qt.Key_L, Qt.ControlModifier) }
                    TerminalPillButton { text: "Home"; onClicked: terminalPage.terminalBackend.sendKey(Qt.Key_Home) }
                    TerminalPillButton { text: "End"; onClicked: terminalPage.terminalBackend.sendKey(Qt.Key_End) }
                    TerminalPillButton { text: "PgUp"; onClicked: terminalPage.terminalBackend.sendKey(Qt.Key_PageUp) }
                    TerminalPillButton { text: "PgDn"; onClicked: terminalPage.terminalBackend.sendKey(Qt.Key_PageDown) }
                    TerminalPillButton { text: "Paste"; accentColor: "#81A1C1"; onClicked: terminalPage.terminalBackend.pasteFromClipboard() }

                    TerminalPillButton {
                        text: terminalView.selectionMode ? "Done" : "Select"
                        active: terminalView.selectionMode
                        accentColor: "#81A1C1"
                        onClicked: {
                            if (terminalView.selectionMode) terminalView.clearSelection()
                            else terminalView.selectionMode = true
                        }
                    }

                    TerminalPillButton {
                        text: "Copy"
                        enabled: terminalView.selectionActive
                        accentColor: "#8FBCBB"
                        onClicked: {
                            terminalView.copySelection()
                            terminalView.clearSelection()
                            terminalPage.showToast("Copied to clipboard")
                        }
                    }

                    TerminalPillButton {
                        text: "Bottom"
                        accentColor: "#81A1C1"
                        onClicked: {
                            terminalView.followOutput = true
                            terminalView.scrollToBottom()
                        }
                    }

                    TerminalPillButton { text: "Clear"; accentColor: "#4C566A"; onClicked: terminalPage.terminalBackend.clearTerminal() }
                    TerminalPillButton { text: "Reset"; prominent: true; accentColor: "#81A1C1"; onClicked: terminalPage.terminalBackend.resetTerminal() }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            TerminalView {
                id: terminalView
                anchors.fill: parent
                anchors.margins: 14
                terminalBackend: terminalPage.terminalBackend
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width * 0.82, 304)
                height: stoppedContent.implicitHeight + 36
                radius: 14
                color: "#161B24"
                border.color: "#2F3847"
                border.width: 1
                visible: !terminalPage.terminalBackend.running

                ColumnLayout {
                    id: stoppedContent
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 14

                    Text {
                        text: "Terminal session stopped"
                        color: "white"
                        font.pixelSize: 18
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: terminalPage.terminalBackend.statusText
                        color: "#9DA9B8"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    TerminalPillButton {
                        text: "Restart Shell"
                        compact: false
                        prominent: true
                        accentColor: "#81A1C1"
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        onClicked: terminalPage.terminalBackend.resetTerminal()
                    }
                }
            }
        }
    }

    CustomKeyboard {
        id: terminalKeyboard
        parent: terminalPage
        width: parent.width
        z: 999
        visible: keyboardVisible
        terminalMode: true
        terminalTarget: terminalPage.terminalBackend
    }

    Rectangle {
        id: toastBubble
        parent: terminalPage
        z: 1001
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(12, (terminalKeyboard.visible ? terminalKeyboard.y : terminalPage.height) - height - 12)
        implicitWidth: toastText.implicitWidth + 28
        implicitHeight: toastText.implicitHeight + 14
        radius: 18
        color: "#2A71D0"
        opacity: toastMessage !== "" ? 0.95 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on y { NumberAnimation { duration: 180 } }

        Text {
            id: toastText
            anchors.margins: 14
            anchors.centerIn: parent
            text: toastMessage
            color: "white"
            font.pixelSize: 12
            font.bold: true
        }
    }

    Timer {
        id: toastTimer
        interval: 1800
        onTriggered: toastMessage = ""
    }
}
