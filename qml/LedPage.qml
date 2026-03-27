import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import MyDesktop.Backend 1.0

Page {
    id: ledPage
    background: Rectangle { color: "#121212" }

    property var backend
    property var ledCtrl: backend ? backend.ledBackend : null
    property string selectedModeLabel: ledCtrl ? ledModeLabel(ledCtrl.currentMode) : ""

    function ledTriggerLabel(trigger) {
        if (!trigger || trigger === "none")
            return "Manual"
        if (trigger === "default-on")
            return "Always On"
        return trigger
    }

    function ledModeLabel(modeId) {
        if (!ledCtrl)
            return ""

        for (var i = 0; i < ledCtrl.modeOptions.length; ++i) {
            var option = ledCtrl.modeOptions[i]
            if (option.id === modeId)
                return option.label
        }

        if (modeId === "custom")
            return "Custom / Mixed"

        return "Manual"
    }

    component AccentSlider : Slider {
        id: control
        property color accentColor: "#0079DB"

        Layout.fillWidth: true
        from: 0
        to: 100
        stepSize: 1

        background: Rectangle {
            x: control.leftPadding
            y: control.topPadding + control.availableHeight / 2 - height / 2
            implicitWidth: 200
            implicitHeight: 4
            width: control.availableWidth
            height: implicitHeight
            radius: 2
            color: "#333"

            Rectangle {
                width: control.visualPosition * parent.width
                height: parent.height
                color: control.accentColor
                radius: 2
            }
        }

        handle: Rectangle {
            x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
            y: control.topPadding + control.availableHeight / 2 - height / 2
            implicitWidth: 24
            implicitHeight: 24
            radius: 12
            color: control.pressed ? "#f0f0f0" : "#ffffff"
            border.color: control.accentColor
        }
    }

    component ActionChip : Rectangle {
        id: chip
        property alias text: chipText.text
        property bool active: false
        signal tapped()

        implicitWidth: 104
        implicitHeight: 36
        radius: 17
        color: active ? "#0079DB" : (tapHandler.pressed ? "#2a2a2a" : "#1e1e1e")
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
            id: tapHandler
            onTapped: chip.tapped()
        }
    }

    component SectionCard : Rectangle {
        color: "#1e1e1e"
        radius: 12
        Layout.fillWidth: true
        Layout.leftMargin: 20
        Layout.rightMargin: 20
    }

    Popup {
        id: modeNamePopup
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.min(parent.width * 0.86, 320)
        height: modePopupLayout.implicitHeight + 40
        padding: 20
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        Overlay.modal: Rectangle { color: "#88000000" }

        background: Rectangle {
            color: "#1e1e1e"
            radius: 16
            border.color: "#3b4658"
            border.width: 1
        }

        contentItem: ColumnLayout {
            id: modePopupLayout
            spacing: 10

            Text {
                text: "Current Mode"
                color: "#888"
                font.pixelSize: 12
            }

            Text {
                Layout.fillWidth: true
                text: ledPage.selectedModeLabel
                color: "white"
                font.pixelSize: 18
                font.bold: true
                wrapMode: Text.WordWrap
            }
        }
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
                    text: "LEDs"
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
                visible: !ledCtrl || !ledCtrl.hasLeds
                spacing: 15

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 80
                    height: 80
                    radius: 40
                    color: "#222"

                    IconImage {
                        anchors.centerIn: parent
                        source: "qrc:/MyDesktop/Backend/assets/light.svg"
                        sourceSize: Qt.size(36, 36)
                        color: "#666"
                    }
                }

                Text {
                    text: "No LED device found"
                    color: "#666"
                    font.pixelSize: 16
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            ScrollView {
                id: ledScroll
                anchors.fill: parent
                clip: true
                visible: ledCtrl && ledCtrl.hasLeds
                contentWidth: availableWidth

                ColumnLayout {
                    width: ledScroll.availableWidth
                    spacing: 20

                    Item { height: 10 }

                    SectionCard {
                        implicitHeight: summaryLayout.implicitHeight + 30

                        ColumnLayout {
                            id: summaryLayout
                            anchors.fill: parent
                            anchors.margins: 15
                            spacing: 12

                            RowLayout {
                                Layout.fillWidth: true

                                IconImage {
                                    source: "qrc:/MyDesktop/Backend/assets/light.svg"
                                    sourceSize: Qt.size(24, 24)
                                    color: "white"
                                }

                                Text {
                                    text: "Overview"
                                    color: "white"
                                    font.bold: true
                                    font.pixelSize: 16
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true

                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: currentModeColumn.implicitHeight
                                    clip: true

                                    ColumnLayout {
                                        id: currentModeColumn
                                        anchors.left: parent.left
                                        width: parent.width
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4

                                        Text {
                                            text: "Current Mode"
                                            color: "#888"
                                            font.pixelSize: 12
                                            width: parent.width
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                        }

                                        Text {
                                            text: ledPage.ledModeLabel(ledCtrl.currentMode)
                                            color: "white"
                                            font.pixelSize: 18
                                            font.bold: true
                                            width: parent.width
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                        }

                                        Text {
                                            text: "Tap to view full name"
                                            color: "#888"
                                            font.pixelSize: 11
                                            width: parent.width
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                        }

                                        TapHandler {
                                            onTapped: {
                                                ledPage.selectedModeLabel = ledPage.ledModeLabel(ledCtrl.currentMode)
                                                modeNamePopup.open()
                                            }
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: devicesColumn.implicitHeight

                                    ColumnLayout {
                                        id: devicesColumn
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4

                                        Text {
                                            text: "Devices"
                                            color: "#888"
                                            font.pixelSize: 12
                                            horizontalAlignment: Text.AlignHCenter
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        Text {
                                            text: ledCtrl.leds.length
                                            color: "white"
                                            font.pixelSize: 18
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    SectionCard {
                        implicitHeight: modeLayout.implicitHeight + 30

                        ColumnLayout {
                            id: modeLayout
                            anchors.fill: parent
                            anchors.margins: 15
                            spacing: 12

                            Text {
                                text: "Mode"
                                color: "white"
                                font.bold: true
                                font.pixelSize: 16
                            }

                            Text {
                                text: "Switch all LEDs to the same hardware trigger."
                                color: "#888"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Flow {
                                Layout.fillWidth: true
                                width: parent.width
                                spacing: 8

                                Repeater {
                                    model: ledCtrl.modeOptions

                                    delegate: ActionChip {
                                        text: modelData.label
                                        active: ledCtrl.currentMode === modelData.id
                                        onTapped: ledCtrl.setMode(modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    SectionCard {
                        implicitHeight: brightnessLayout.implicitHeight + 30

                        ColumnLayout {
                            id: brightnessLayout
                            anchors.fill: parent
                            anchors.margins: 15
                            spacing: 12

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "All LED Brightness"
                                    color: "white"
                                    font.pixelSize: 16
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: ledCtrl.allLedBrightness.toFixed(0) + "%"
                                    color: "#aaa"
                                    font.pixelSize: 12
                                }
                            }

                            AccentSlider {
                                accentColor: "#D98D00"
                                value: ledCtrl.allLedBrightness
                                onMoved: ledCtrl.setAllLedBrightness(value)
                            }

                            Flow {
                                Layout.fillWidth: true
                                width: parent.width
                                spacing: 8

                                ActionChip {
                                    text: "Off"
                                    onTapped: ledCtrl.setAllLedBrightness(0)
                                }

                                ActionChip {
                                    text: "Half"
                                    onTapped: ledCtrl.setAllLedBrightness(50)
                                }

                                ActionChip {
                                    text: "On"
                                    onTapped: ledCtrl.setAllLedBrightness(100)
                                }
                            }
                        }
                    }

                    SectionCard {
                        visible: ledCtrl.supportsFlash
                        implicitHeight: flashLayout.implicitHeight + 30

                        ColumnLayout {
                            id: flashLayout
                            anchors.fill: parent
                            anchors.margins: 15
                            spacing: 12

                            Text {
                                text: "Flash"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                            }

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "Flash Brightness"
                                    color: "white"
                                    font.pixelSize: 14
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: ledCtrl.allLedFlashBrightness.toFixed(0) + "%"
                                    color: "#aaa"
                                    font.pixelSize: 12
                                }
                            }

                            AccentSlider {
                                accentColor: "#FFB020"
                                value: ledCtrl.allLedFlashBrightness
                                onMoved: ledCtrl.setAllLedFlashBrightness(value)
                            }

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "Flash Duration"
                                    color: "white"
                                    font.pixelSize: 14
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: ledCtrl.allLedFlashTimeoutMs.toFixed(0) + " ms"
                                    color: "#aaa"
                                    font.pixelSize: 12
                                }
                            }

                            AccentSlider {
                                accentColor: "#FFB020"
                                from: 10
                                to: Math.max(10, ledCtrl.maxLedFlashTimeoutMs)
                                stepSize: 10
                                value: Math.max(10, ledCtrl.allLedFlashTimeoutMs)
                                onMoved: ledCtrl.setAllLedFlashTimeoutMs(value)
                            }

                            Flow {
                                Layout.fillWidth: true
                                width: parent.width
                                spacing: 8

                                ActionChip {
                                    text: "Flash All"
                                    onTapped: ledCtrl.flashAllLeds()
                                }
                            }
                        }
                    }

                    Repeater {
                        model: ledCtrl.leds

                        delegate: SectionCard {
                            id: ledCard
                            property var ledData: modelData
                            property string ledName: modelData.name
                            property real liveBrightness: modelData.brightness
                            implicitHeight: ledLayout.implicitHeight + 30

                            onLedDataChanged: {
                                if (!ledBrightnessSlider.pressed)
                                    liveBrightness = ledData.brightness
                            }

                            ColumnLayout {
                                id: ledLayout
                                anchors.fill: parent
                                anchors.margins: 15
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        text: ledCard.ledData.displayName
                                        color: "white"
                                        font.pixelSize: 16
                                        font.bold: true
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: ledPage.ledTriggerLabel(ledCard.ledData.trigger)
                                        color: "#888"
                                        font.pixelSize: 12
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        text: "Brightness"
                                        color: "white"
                                        font.pixelSize: 14
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: ledCard.liveBrightness.toFixed(0) + "%"
                                        color: "#aaa"
                                        font.pixelSize: 12
                                    }
                                }

                                AccentSlider {
                                    accentColor: "#26A8FF"
                                    id: ledBrightnessSlider
                                    value: ledCard.liveBrightness
                                    onMoved: {
                                        ledCard.liveBrightness = value
                                    }
                                    onPressedChanged: {
                                        if (!pressed) {
                                            ledCtrl.setLedBrightness(ledCard.ledName, ledCard.liveBrightness)
                                        }
                                    }
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    width: parent.width
                                    spacing: 8

                                    ActionChip {
                                        text: "Off"
                                        onTapped: {
                                            ledCard.liveBrightness = 0
                                            ledCtrl.setLedBrightness(ledCard.ledName, 0)
                                        }
                                    }

                                    ActionChip {
                                        text: "On"
                                        onTapped: {
                                            ledCard.liveBrightness = 100
                                            ledCtrl.setLedBrightness(ledCard.ledName, 100)
                                        }
                                    }

                                    ActionChip {
                                        visible: ledCard.ledData.supportsFlash
                                        text: "Flash"
                                        onTapped: ledCtrl.flashLed(ledCard.ledName)
                                    }
                                }
                            }
                        }
                    }

                    Item { height: 20 }
                }
            }
        }
    }
}
