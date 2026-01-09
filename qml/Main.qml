import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyDesktop.Backend 1.0

Window {
    width: 360
    height: 720
    visible: true
    title: "OP6T Dashboard"
    color: "#121212"

    SystemMonitor {
        id: backend
    }

    Popup {
        id: cpuDetailsPopup
        // 使用 Overlay.overlay 作为父级，确保它浮在整个窗口最上层，不受 Layout 限制
        parent: Overlay.overlay 
        
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.85
        height: parent.height * 0.6
        
        modal: true // 开启模态，这会自动在背景层加一个半透明遮罩
        focus: true
        
        // 确保关闭策略包含点击外部
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        // 自定义遮罩层样式 (可选，让背景变暗一点，更有沉浸感)
        Overlay.modal: Rectangle {
            color: "#aa000000" // 黑色半透明
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200 }
        }
        
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: 200 }
        }

        background: Rectangle {
            color: "#1e1e1e"
            radius: 15
            border.color: "#333333"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 20

            Text {
                text: "CPU Core Details"
                color: "white"
                font.pixelSize: 20
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 10
            }

            // 条形图列表
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: backend.cpuCores
                spacing: 15
                clip: true
                
                delegate: ColumnLayout {
                    width: cpuDetailsPopup.width - 40
                    spacing: 5
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text { 
                            text: "Core " + index
                            color: "#aaaaaa"
                            font.pixelSize: 14 
                        }
                        Item { Layout.fillWidth: true }
                        Text { 
                            text: (modelData * 100).toFixed(1) + "%"
                            color: "white"
                            font.family: "Monospace"
                        }
                    }

                    // 进度条背景
                    Rectangle {
                        Layout.fillWidth: true
                        height: 12
                        color: "#333333"
                        radius: 6

                        // 进度条填充
                        Rectangle {
                            width: parent.width * modelData
                            height: parent.height
                            color: modelData > 0.8 ? "#FF5252" : "#FFD740" // 高负载变红
                            radius: 6
                            
                            // 简单的动画平滑过渡
                            Behavior on width {
                                NumberAnimation { duration: 500; easing.type: Easing.OutExpo }
                            }
                        }
                    }
                }
            }

            Button {
                text: "Close"
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 10
                onClicked: cpuDetailsPopup.close()
                
                background: Rectangle {
                    implicitWidth: 100
                    implicitHeight: 40
                    color: "#333333"
                    radius: 20
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: mainCol.height + 40
        clip: true

        ColumnLayout {
            id: mainCol
            width: parent.width - 20
            x: 10
            y: 20
            spacing: 15

            // --- 标题 ---
            Text {
                text: "Server Status"
                color: "white"
                font.bold: true
                font.pixelSize: 24
                Layout.leftMargin: 5
            }

            // --- 第一行：CPU 和 内存 环形图 ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 15

                // CPU 卡片
                Rectangle {
                    id: cpuCard
                    Layout.fillWidth: true
                    height: 180
                    color: tapHandler.pressed ? "#2a2a2a" : "#1e1e1e" // 点击时颜色反馈
                    radius: 12

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 15
                        Text { text: "CPU Load"; color: "#dddddd"; font.bold: true }

                        CircleProgress {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 100
                            Layout.preferredHeight: 100
                            value: backend.cpuTotal
                            centerText: (backend.cpuTotal * 100).toFixed(0) + "%"
                            subText: "Tap for Details"
                            primaryColor: "#FF5252"
                        }
                        
                        // 底部迷你核心指示器（保留）
                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4
                            Repeater {
                                model: backend.cpuCores
                                Rectangle {
                                    width: 8; height: 8; radius: 2
                                    color: modelData > 0.1 ? "#FF5252" : "#333333"
                                }
                            }
                        }
                    }

                    // 点击区域
                    TapHandler {
                        id: tapHandler
                        enabled: !cpuDetailsPopup.visible
                                                
                        onTapped: {
                            console.log("Tap detected!")
                            cpuDetailsPopup.open()
                        }
                    }
                }

                // 内存 卡片
                Rectangle {
                    Layout.fillWidth: true
                    height: 180
                    color: "#1e1e1e"
                    radius: 12

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 15
                        Text { text: "Memory"; color: "#dddddd"; font.bold: true }

                        CircleProgress {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 100
                            Layout.preferredHeight: 100
                            value: backend.memPercent
                            centerText: (backend.memPercent * 100).toFixed(0) + "%"
                            primaryColor: "#4CAF50"
                        }
                        
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: backend.memDetail
                            color: "#aaaaaa"
                            font.pixelSize: 12
                        }
                    }
                }
            }

            // --- 占位区域：历史曲线 (Line Chart) ---
            Rectangle {
                Layout.fillWidth: true
                height: 150
                color: "#1e1e1e"
                radius: 12
                border.color: "#333333"
                border.width: 1 // 虚线效果需 Canvas，这里暂用实线

                Text {
                    anchors.centerIn: parent
                    text: "[ TODO: History Line Chart ]\nCPU / Mem Trends"
                    color: "#555555"
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // --- 占位区域：硬盘 (Disk) ---
            Rectangle {
                Layout.fillWidth: true
                height: 80
                color: "#1e1e1e"
                radius: 12
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 15
                    Text { text: "Disk Usage (Root)"; color: "white" }
                    Item { Layout.fillWidth: true }
                    Text { text: "[ Pending ]"; color: "#FF9800" }
                }
            }

            // --- 占位区域：网络 (Network) ---
            Rectangle {
                Layout.fillWidth: true
                height: 80
                color: "#1e1e1e"
                radius: 12

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 15
                    Text { text: "Network (wlan0)"; color: "white" }
                    Item { Layout.fillWidth: true }
                    Text { text: "↓ 0 KB/s  ↑ 0 KB/s"; color: "#2196F3" }
                }
            }
            
            // 底部留白
            Item { height: 20 }
        }
    }
}