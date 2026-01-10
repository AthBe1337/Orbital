import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#121212"

    // --- 外部接口 ---
    // 1. 接收后端数据对象
    required property var sysMon
    // 2. 发出返回信号，由 Main.qml 处理导航
    signal requestBack()

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
                spacing: 0 // 移除间距，由按钮自己控制

                // 【核心修复】增大返回按钮的点击区域
                ToolButton {
                    // 强制设置按钮大小为 48x48 (标准触控尺寸)
                    Layout.preferredWidth: 48 
                    Layout.fillHeight: true 
                    
                    // 自定义内容，确保箭头居中
                    contentItem: Text { 
                        text: "◀"
                        color: "white"
                        font.pixelSize: 20 // 稍微调大箭头
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    background: Rectangle { 
                        color: parent.pressed ? "#333" : "transparent" 
                    }
                    
                    // 发出信号
                    onClicked: root.requestBack()
                }

                Text {
                    text: "Settings"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 18
                    Layout.leftMargin: 10 // 文字左边距
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
                                sourceSize: Qt.size(22, 22)
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
                                    color: "#00E676"
                                    radius: 2
                                }
                            }
                            handle: Rectangle {
                                x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                                y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                implicitWidth: 24; implicitHeight: 24
                                radius: 12
                                color: brightnessSlider.pressed ? "#f0f0f0" : "#ffffff"
                                border.color: "#00E676"
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; Layout.leftMargin: 20; Layout.rightMargin: 20
                    height: 60; color: "#1e1e1e"; radius: 12
                    
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
                            text: sysMon.wifiList.length > 0 && sysMon.wifiList[0].connected ? sysMon.wifiList[0].ssid : "Not Connected"
                            color: "#888"; font.pixelSize: 12
                        }
                        Text { text: "›"; color: "#666"; font.pixelSize: 20 }
                    }
                    
                    TapHandler {
                        onTapped: {
                            // 跳转到 WiFi 页面
                            stackView.push("qrc:/MyDesktop/Backend/qml/WifiPage.qml", { "backend": sysMon })
                        }
                    }
                }
                
                // 占位：更多设置
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    height: 60
                    color: "#1e1e1e"
                    radius: 12
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 15
                        Text { text: "About"; color: "white"; font.bold: true; font.pixelSize: 16 }
                        Item { Layout.fillWidth: true }
                        Text { text: "Orbital " + appBuildHash; color: "#555"; font.italic: true }
                    }
                }

                Item { height: 20 }
            }
        }
    }
}