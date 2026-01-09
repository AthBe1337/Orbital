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
                    Layout.fillWidth: true
                    height: 180
                    color: "#1e1e1e"
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
                            subText: "8 Cores"
                            primaryColor: "#FF5252"
                        }
                        
                        // 核心占用率微型展示 (GridLayout inside)
                        GridLayout {
                            columns: 4
                            Layout.fillWidth: true
                            columnSpacing: 2
                            rowSpacing: 2
                            
                            Repeater {
                                model: backend.cpuCores
                                Rectangle {
                                    // 动态计算条高度，模拟一种频谱图效果
                                    Layout.preferredWidth: (parent.width - 10) / 4
                                    Layout.preferredHeight: 4
                                    color: "#333333"
                                    Rectangle {
                                        width: parent.width * modelData
                                        height: parent.height
                                        color: "#FF5252"
                                    }
                                }
                            }
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