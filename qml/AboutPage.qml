import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyDesktop.Backend 1.0

Page {
    id: aboutPage
    background: Rectangle { color: "#121212" }

    property var backend // 从外部传入 SystemMonitor 实例

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ============================================================
        // 1. 标题栏
        // ============================================================
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
                    text: "About"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 25
                    Layout.leftMargin: 5
                }
                
                Item { Layout.fillWidth: true }
            }
        }

        // ============================================================
        // 2. Logo 和应用名
        // ============================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            ColumnLayout {
                anchors.centerIn: parent
                // 【调整】增加间距，防止溢出的 Logo 碰到下面的文字
                spacing: 40 

                // Logo 圆盘背景
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    
                    property real size: aboutPage.width * 0.65
                    
                    Layout.preferredWidth: size
                    Layout.preferredHeight: size
                    radius: size / 2
                    
                    color: "#1e1e1e" // 灰色托盘
                    
                    // 确保不裁剪超出部分
                    clip: false 

                    IconImage {
                        anchors.centerIn: parent
                        source: "qrc:/MyDesktop/Backend/assets/logo.svg" 
                        
                        // Logo 放大并超出：设为圆盘大小的 1.2 倍 (120%)
                        width: parent.width * 1.2
                        height: parent.height * 1.2
                        sourceSize: Qt.size(width, height)
                        
                        color: "white"
                        fillMode: Image.PreserveAspectFit
                    }
                }

                // App Name
                Text {
                    text: "Orbital"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 32
                    Layout.alignment: Qt.AlignHCenter
                }
                
                Text {
                    text: "\"Don't ask how we lost our way,"
                    color: "#888"
                    font.pixelSize: 14
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "Follow the stars to the place where we used to lay.\""
                    color: "#888"
                    font.pixelSize: 14
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // ============================================================
        // 3. 系统信息列表
        // ============================================================
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 20; Layout.rightMargin: 20
            Layout.bottomMargin: 40
            
            // 高度根据内容自适应
            height: infoCol.implicitHeight + 30
            color: "#1e1e1e"
            radius: 12

            ColumnLayout {
                id: infoCol
                anchors.fill: parent
                anchors.margins: 15
                spacing: 0 

                // --- 1. Orbital Version ---
                InfoRow {
                    label: "Orbital Version"
                    // 直接调用全局变量 appBuildHash
                    value: (typeof appBuildHash !== "undefined") ? appBuildHash : "Unknown"
                    icon: "qrc:/MyDesktop/Backend/assets/info.svg" 
                }

                Rectangle { 
                    Layout.fillWidth: true; height: 1; color: "#333" 
                    Layout.topMargin: 10; Layout.bottomMargin: 10
                }

                // --- 2. System Version (读取 /etc/os-release) ---
                InfoRow {
                    label: "System"
                    value: backend ? backend.osVersion : "--"
                    icon: "qrc:/MyDesktop/Backend/assets/settings.svg" 
                }
            }
        }
    }

    // --- 内部组件：信息行封装 ---
    component InfoRow : RowLayout {
        property string label: ""
        property string value: ""
        property string icon: ""

        spacing: 15
        
        // 左侧图标
        Item {
            Layout.preferredWidth: 24; Layout.preferredHeight: 24
            IconImage {
                anchors.centerIn: parent
                source: parent.parent.icon
                sourceSize: Qt.size(20, 20)
                color: "#888"
            }
        }

        // 文本信息
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            
            Text {
                text: parent.parent.label
                color: "#888"
                font.pixelSize: 12
            }
            Text {
                text: parent.parent.value
                color: "white"
                font.pixelSize: 16
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }
}