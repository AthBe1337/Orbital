import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#121212"

    // --- 外部接口 ---
    // 1. 接收后端数据对象
    required property var sysMon
    // 2. 发出返回信号，由 Main.qml 处理导航
    signal requestBack()
    property var ledCtrl: root.sysMon ? root.sysMon.ledBackend : null

    function ledModeLabel(modeId) {
        if (!root.ledCtrl)
            return ""

        for (var i = 0; i < root.ledCtrl.modeOptions.length; ++i) {
            var option = root.ledCtrl.modeOptions[i]
            if (option.id === modeId)
                return option.label
        }

        if (modeId === "custom")
            return "Custom / Mixed"

        return "Manual"
    }

    function screenOffMethodLabel(method) {
        if (method === "backlight")
            return "Backlight only"
        return "DRM DPMS"
    }

    // seconds -> Never / 30s / 2 min / 1.5 min (steps are 30s)
    function screenOffTimeoutLabel(sec) {
        if (!sec || sec <= 0)
            return "Never"
        if (sec < 60)
            return sec + "s"
        var mins = sec / 60
        if (Math.floor(mins) === mins)
            return mins + " min"
        return mins.toFixed(1) + " min"
    }

    Popup {
        id: screenOffPopup
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.85
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        Overlay.modal: Rectangle { color: "#aa000000" }

        // Pending values, applied to sysMon only on OK; Cancel discards.
        // pendingSteps: 0 = never (power key only), 1..60 = 0.5..30 min.
        property int pendingSteps: 0
        property string pendingMethod: "dpms"

        onOpened: {
            pendingMethod = root.sysMon ? root.sysMon.screenOffMethod : "dpms"
            var cur = root.sysMon ? root.sysMon.screenOffTimeoutSec : 120
            if (cur > 0) {
                pendingSteps = Math.round(cur / 30)
                if (pendingSteps < 1)
                    pendingSteps = 1
                if (pendingSteps > 60)
                    pendingSteps = 60
            } else {
                pendingSteps = 0
            }
        }

        background: Rectangle {
            color: "#1e1e1e"
            radius: 15
            border.color: "#333333"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 14

            Text {
                text: "Screen Off"
                color: "white"
                font.pixelSize: 18
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
            }

            Text {
                text: "Screen Off Method"
                color: "#888"
                font.pixelSize: 12
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
            }

            Repeater {
                model: [
                    { id: "dpms",      label: "DRM DPMS",      detail: "Recommended. Uses kernel DPMS via DRM connector plus backlight off." },
                    { id: "backlight", label: "Backlight only", detail: "Compatibility mode. Skips DRM DPMS; only turns the backlight off." }
                ]

                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    height: Math.max(optCol.implicitHeight + 28, 74)
                    radius: 10
                    color: optTap.pressed ? "#2a2a2a" : "#252525"
                    border.color: screenOffPopup.pendingMethod === modelData.id ? "#0079DB" : "#333"
                    border.width: 1

                    ColumnLayout {
                        id: optCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: modelData.label
                                color: "white"
                                font.pixelSize: 15
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: screenOffPopup.pendingMethod === modelData.id
                                text: "✓"
                                color: "#0079DB"
                                font.pixelSize: 16
                                font.bold: true
                            }
                        }

                        Text {
                            text: modelData.detail
                            color: "#888"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    TapHandler {
                        id: optTap
                        onTapped: screenOffPopup.pendingMethod = modelData.id
                    }
                }
            }

            Text {
                text: "Auto Screen Off"
                color: "#888"
                font.pixelSize: 12
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
            }

            Text {
                text: screenOffPopup.pendingSteps <= 0 ? "Never (power key only)" : root.screenOffTimeoutLabel(screenOffPopup.pendingSteps * 30)
                color: "#0079DB"
                font.pixelSize: 22
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Slider {
                id: timeoutSlider
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                from: 1
                to: 60
                stepSize: 1
                enabled: screenOffPopup.pendingSteps > 0
                opacity: screenOffPopup.pendingSteps > 0 ? 1.0 : 0.35
                value: screenOffPopup.pendingSteps > 0 ? screenOffPopup.pendingSteps : 4
                onMoved: screenOffPopup.pendingSteps = Math.round(value)

                background: Rectangle {
                    x: timeoutSlider.leftPadding
                    y: timeoutSlider.topPadding + timeoutSlider.availableHeight / 2 - height / 2
                    implicitWidth: 200; implicitHeight: 4
                    width: timeoutSlider.availableWidth; height: implicitHeight
                    radius: 2; color: "#333"
                    Rectangle {
                        width: timeoutSlider.visualPosition * parent.width
                        height: parent.height
                        color: "#0079DB"
                        radius: 2
                    }
                }
                handle: Rectangle {
                    x: timeoutSlider.leftPadding + timeoutSlider.visualPosition * (timeoutSlider.availableWidth - width)
                    y: timeoutSlider.topPadding + timeoutSlider.availableHeight / 2 - height / 2
                    implicitWidth: 24; implicitHeight: 24
                    radius: 12
                    color: timeoutSlider.pressed ? "#f0f0f0" : "#ffffff"
                    border.color: "#0079DB"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Text { text: "30s"; color: "#888"; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Text { text: "30 min"; color: "#888"; font.pixelSize: 11 }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.preferredHeight: 48
                radius: 8
                color: tapAutoToggle.pressed ? "#3a3a3a" : "#252525"
                border.color: "#555"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: screenOffPopup.pendingSteps > 0 ? "Disable auto screen-off" : "Enable auto screen-off"
                    color: "white"
                    font.pixelSize: 15
                }
                TapHandler {
                    id: tapAutoToggle
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: {
                    if (screenOffPopup.pendingSteps > 0)
                        screenOffPopup.pendingSteps = 0
                    else
                        screenOffPopup.pendingSteps = 4
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 8
                    color: tapCancel.pressed ? "#3a3a3a" : "#252525"
                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: "#aaa"
                        font.pixelSize: 15
                    }
                    TapHandler {
                        id: tapCancel
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: screenOffPopup.close()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 8
                    color: tapOK.pressed ? "#005FA3" : "#0079DB"
                    Text {
                        anchors.centerIn: parent
                        text: "OK"
                        color: "white"
                        font.bold: true
                        font.pixelSize: 15
                    }
                    TapHandler {
                        id: tapOK
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: {
                        if (root.sysMon) {
                            root.sysMon.screenOffMethod = screenOffPopup.pendingMethod
                            var secs = screenOffPopup.pendingSteps <= 0 ? 0 : screenOffPopup.pendingSteps * 30
                            root.sysMon.screenOffTimeoutSec = secs
                        }
                        screenOffPopup.close()
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 6 }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- 标题栏 ---
        Rectangle {
            Layout.fillWidth: true
            height: 52 // 稍微增高一点
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
                        onTapped: root.requestBack()
                    }
                }

                Text {
                    text: "Settings"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 25
                    Layout.leftMargin: 5 // 文字左边距
                }
                
                Item { Layout.fillWidth: true }
            }
        }

        // --- 内容区域 ---
        ScrollView {
            id: settingScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            
            contentWidth: availableWidth 

            ColumnLayout {
                width: settingScroll.availableWidth 
                spacing: 20
                
                Item { height: 10 } 

                // 1. 亮度控制
                Rectangle {
                    Layout.fillWidth: true; Layout.leftMargin: 20; Layout.rightMargin: 20
                    height: 100; color: "#1e1e1e"; radius: 12
                    
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 15; spacing: 10
                        
                        // 标题行：图标 + 文字 + 数值
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10 // 图标和文字的间距

                            // 1. 亮度图标
                            IconImage {
                                source: "qrc:/MyDesktop/Backend/assets/brightness.svg"
                                sourceSize: Qt.size(24, 24)
                                color: "white"
                            }

                            // 2. 标题文字
                            Text { 
                                text: "Brightness"; 
                                color: "white"; 
                                font.bold: true; 
                                font.pixelSize: 16 
                            }

                            Item { Layout.fillWidth: true } // 弹簧

                            // 3. 数值显示
                            Text { 
                                text: brightnessSlider.value.toFixed(0) + "%"; 
                                color: "#aaa" 
                            }
                        }

                        // 滑动条 (保持不变)
                        Slider {
                            id: brightnessSlider
                            Layout.fillWidth: true; from: 0; to: 100; stepSize: 1
                            value: root.sysMon ? root.sysMon.brightness : 50
                            onMoved: if (root.sysMon) root.sysMon.brightness = value
                            
                            background: Rectangle {
                                x: brightnessSlider.leftPadding
                                y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                implicitWidth: 200; implicitHeight: 4
                                width: brightnessSlider.availableWidth; height: implicitHeight
                                radius: 2; color: "#333"
                                Rectangle {
                                    width: brightnessSlider.visualPosition * parent.width
                                    height: parent.height
                                    color: "#0079DB"
                                    radius: 2
                                }
                            }
                            handle: Rectangle {
                                x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                                y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                implicitWidth: 24; implicitHeight: 24
                                radius: 12
                                color: brightnessSlider.pressed ? "#f0f0f0" : "#ffffff"
                                border.color: "#0079DB"
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    height: 60
                    color: tapScreenOff.pressed ? "#2a2a2a" : "#1e1e1e"
                    radius: 12

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 15

                        IconImage {
                            source: "qrc:/MyDesktop/Backend/assets/screen-off.svg"
                            sourceSize: Qt.size(24, 24)
                            color: "white"
                        }

                        Text {
                            text: "Screen Off"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                        }

                        Text {
                            text: root.sysMon ? (root.screenOffMethodLabel(root.sysMon.screenOffMethod) + " · " + root.screenOffTimeoutLabel(root.sysMon.screenOffTimeoutSec)) : ""
                            color: "#888"
                            font.pixelSize: 12
                        }
                    }

                    TapHandler {
                        id: tapScreenOff
                        onTapped: screenOffPopup.open()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    height: 60
                    visible: root.ledCtrl && root.ledCtrl.hasLeds
                    color: tapLed.pressed ? "#2a2a2a" : "#1e1e1e"
                    radius: 12

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 15

                        IconImage {
                            source: "qrc:/MyDesktop/Backend/assets/light.svg"
                            sourceSize: Qt.size(24, 24)
                            color: "white"
                        }

                        Text {
                            text: "LEDs"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                        }

                        Text {
                            text: root.ledModeLabel(root.ledCtrl.currentMode)
                            color: "#888"
                            font.pixelSize: 12
                        }
                    }

                    TapHandler {
                        id: tapLed
                        onTapped: {
                            stackView.push("qrc:/MyDesktop/Backend/qml/LedPage.qml", {
                                "backend": root.sysMon
                            })
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; Layout.leftMargin: 20; Layout.rightMargin: 20
                    height: 60
                    color: tapWifi.pressed ? "#2a2a2a" : "#1e1e1e"
                    radius: 12
                    
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 15
                        IconImage { 
                            source: "qrc:/MyDesktop/Backend/assets/wifi.svg"
                            sourceSize: Qt.size(24, 24); color: "white" 
                        }
                        Text { 
                            text: "WLAN"
                            color: "white"; font.pixelSize: 16; font.bold: true
                            Layout.fillWidth: true; Layout.leftMargin: 10
                        }
                        Text { 
                            // 显示当前连接的 SSID
                            text: sysMon.wifiEnabled ? (sysMon.wifiList.length > 0 && sysMon.wifiList[0].connected ? sysMon.wifiList[0].ssid : "Not Connected") : "Off"
                            color: "#888"; font.pixelSize: 12
                        }
                    }
                    
                    TapHandler {
                        id: tapWifi
                        onTapped: {
                            // 跳转到 WiFi 页面
                            stackView.push("qrc:/MyDesktop/Backend/qml/WifiPage.qml", { "backend": sysMon })
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    height: 60
                    color: tapDetails.pressed ? "#2a2a2a" : "#1e1e1e"
                    radius: 12

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 15

                        IconImage {
                            source: "qrc:/MyDesktop/Backend/assets/list.svg"
                            sourceSize: Qt.size(24, 24)
                            color: "white"
                        }

                        Text {
                            text: "System Details"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                        }
                    }

                    TapHandler {
                        id: tapDetails
                        onTapped: {
                            stackView.push("qrc:/MyDesktop/Backend/qml/SystemDetailsPage.qml", {
                                "backend": root.sysMon
                            })
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    height: 60
                    color: tapPlugins.pressed ? "#2a2a2a" : "#1e1e1e"
                    radius: 12

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 15

                        IconImage {
                            source: "qrc:/MyDesktop/Backend/assets/plug.svg"
                            sourceSize: Qt.size(24, 24)
                            color: "white"
                        }

                        Text {
                            text: "Plugins"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                        }

                        Text {
                            text: {
                                if (!root.sysMon || !root.sysMon.pluginManager)
                                    return ""
                                var n = root.sysMon.pluginManager.plugins.length
                                return n + (n === 1 ? " plugin" : " plugins")
                            }
                            color: "#888"
                            font.pixelSize: 12
                        }
                    }

                    TapHandler {
                        id: tapPlugins
                        onTapped: {
                            stackView.push("qrc:/MyDesktop/Backend/qml/PluginsPage.qml", {
                                "backend": root.sysMon
                            })
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    height: 60
                    color: tapAbout.pressed ? "#2a2a2a" : "#1e1e1e"
                    radius: 12
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 15
                        IconImage {
                            source: "qrc:/MyDesktop/Backend/assets/info.svg"
                            sourceSize: Qt.size(24, 24); color: "white"
                        }
                        Text {
                            text: "About"
                            color: "white"; font.pixelSize: 16; font.bold: true
                            Layout.fillWidth: true; Layout.leftMargin: 10
                        }
                    }

                    TapHandler {
                        id: tapAbout
                        onTapped: {
                            // 显示关于信息
                            stackView.push("qrc:/MyDesktop/Backend/qml/AboutPage.qml", {
                                "backend": root.sysMon
                            })
                        }
                    }
                }

                Item { height: 20 }
            }
        }
    }
}
