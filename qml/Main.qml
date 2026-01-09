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

    // --- 1. CPU 配色 (经典性能监控色: 绿 -> 黄 -> 红) ---
    function cpuColor(v) {
        var value = Math.max(0, Math.min(1, v));
        if (value < 0.4) return "#4CAF50"; // Green
        if (value < 0.7) return "#FFC107"; // Amber
        return "#FF5252"; // Red
    }

    // --- 2. 内存 配色 (科技冷色调: 蓝 -> 紫 -> 粉红) ---
    function memColor(v) {
        var value = Math.max(0, Math.min(1, v));
        if (value < 0.5) return "#2196F3"; // Blue
        if (value < 0.8) return "#9C27B0"; // Purple
        return "#E91E63"; // Pink/Red
    }

    // --- 3. 硬盘 配色 (数据存储色: 青 -> 橙 -> 红) ---
    function diskColor(v) {
        var value = Math.max(0, Math.min(1, v));
        if (value < 0.6) return "#00E5FF"; // Cyan
        if (value < 0.85) return "#FF9800"; // Orange
        return "#FF5252"; // Red
    }

    // --- 4. 电池 配色 (充电状态优先) ---
    function batteryColor(percent, state) {
        if (state === "Charging") return "#00E676"; // Bright Green
        var p = Math.max(0, Math.min(100, percent));
        if (p >= 80) return "#4CAF50"; 
        if (p >= 30) return "#FFC107"; 
        if (p >= 15) return "#FF9800"; 
        return "#FF5252"; 
    }

    // ================= POPUPS =================

    Popup {
        id: cpuDetailsPopup
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.85
        height: parent.height * 0.6
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        Overlay.modal: Rectangle { color: "#aa000000" }
        
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
            // 顶部留白，替代原来的 Layout.topMargin，布局更稳定
            Item { height: 10; Layout.fillWidth: true } 

            Text {
                text: "CPU Core Details"
                color: "white"
                font.pixelSize: 20
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // 左右留白，防止滚动条贴边
                Layout.leftMargin: 20
                Layout.rightMargin: 20 
                model: backend.cpuCores
                spacing: 15
                clip: true
                
                delegate: ColumnLayout {
                    width: ListView.view.width // 强制宽度与列表一致
                    spacing: 5
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text { 
                            text: "Core " + index
                            color: "#aaaaaa"
                            font.pixelSize: 14 
                        }
                        Item { Layout.fillWidth: true } // 弹簧占位
                        Text { 
                            text: (modelData * 100).toFixed(1) + "%"
                            color: "white"
                            font.family: "Monospace"
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 12
                        color: "#333333"
                        radius: 6
                        Rectangle {
                            width: parent.width * modelData
                            height: parent.height
                            color: modelData > 0.8 ? "#FF5252" : "#FFD740"
                            radius: 6
                            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                        }
                    }
                }
            }
            // 底部留白
            Item { height: 10; Layout.fillWidth: true }
        }
    }

    // 2. 硬盘详情模态框 (Fixed Overflow)
    Popup {
        id: diskPopup
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.9 // 硬盘路径通常较长，给宽一点
        height: parent.height * 0.6
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        Overlay.modal: Rectangle { color: "#aa000000" }
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
            Item { height: 10; Layout.fillWidth: true }

            Text { 
                text: "Storage Partitions"
                color: "white" 
                font.pixelSize: 20 
                font.bold: true 
                Layout.alignment: Qt.AlignHCenter 
            }
            
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 15
                Layout.rightMargin: 15
                model: backend.diskPartitions
                spacing: 10
                clip: true // 防止溢出绘制到圆角外部
                
                delegate: Rectangle {
                    width: ListView.view.width
                    height: 75
                    color: "#2d2d2d"
                    radius: 8
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4
                        
                        // 第一行：挂载点 (左) + 容量 (右)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            
                            Text { 
                                text: modelData.mount
                                color: "white"
                                font.bold: true
                                font.pixelSize: 16
                                // 【关键】防止挂载点过长导致换行或挤出
                                Layout.fillWidth: true 
                                elide: Text.ElideRight 
                            }
                            
                            Text { 
                                text: modelData.used + " / " + modelData.size
                                color: "#aaaaaa"
                                font.pixelSize: 12
                                // 强制不换行，保持右侧对齐
                                Layout.preferredWidth: implicitWidth 
                            }
                        }
                        
                        // 第二行：设备名 (左) + 类型 (左)
                        RowLayout {
                            Layout.fillWidth: true
                            Text { 
                                text: modelData.device
                                color: "#666666"
                                font.pixelSize: 10
                                Layout.maximumWidth: parent.width * 0.6 // 限制设备名最大宽度
                                elide: Text.ElideMiddle // 设备名如果太长，中间省略
                            }
                            Text { 
                                text: "[" + modelData.type + "]"
                                color: "#666666"
                                font.pixelSize: 10
                            }
                        }
                        
                        // 第三行：进度条
                        Rectangle {
                            Layout.fillWidth: true
                            height: 4
                            color: "#444"
                            radius: 2
                            Rectangle { 
                                width: parent.width * modelData.percent
                                height: parent.height
                                color: modelData.percent > 0.9 ? "#FF5252" : "#00E5FF"
                                radius: 2
                            }
                        }
                    }
                }
            }
            Item { height: 10; Layout.fillWidth: true }
        }
    }

    // 3. 电池详情模态框 (Fixed Overflow & Layout)
    Popup {
        id: batPopup
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.85
        height: parent.height * 0.5
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        Overlay.modal: Rectangle { color: "#aa000000" }
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
            Item { height: 10; Layout.fillWidth: true }

            Text { 
                text: "Battery Status"
                color: "white" 
                font.pixelSize: 20 
                font.bold: true 
                Layout.alignment: Qt.AlignHCenter 
            }
            
            // 使用 ListView 替代 GridLayout，处理长内容更灵活
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 25
                Layout.rightMargin: 25
                clip: true
                
                // 将 Map 的 Key 转换为数组模型
                model: Object.keys(backend.batDetails)
                spacing: 12
                
                delegate: RowLayout {
                    width: ListView.view.width
                    spacing: 10
                    
                    // Key (左侧，灰色)
                    Text { 
                        text: modelData
                        color: "#888888"
                        font.pixelSize: 14
                        // 限制 Key 的最大宽度，防止挤压 Value
                        Layout.preferredWidth: parent.width * 0.4 
                        elide: Text.ElideRight 
                    }
                    
                    // Value (右侧，白色，高亮)
                    Text { 
                        text: backend.batDetails[modelData]
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        
                        elide: Text.ElideMiddle 
                    }
                }
            }
            Item { height: 10; Layout.fillWidth: true }
        }
    }

    // ================= MAIN UI =================

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

            Text { text: "Server Status"; color: "white"; font.bold: true; font.pixelSize: 24; Layout.leftMargin: 5 }

            // --- Row 1: CPU & Memory ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 15

                // CPU Card
                Rectangle {
                    Layout.fillWidth: true; height: 160
                    color: tapCpu.pressed ? "#2a2a2a" : "#1e1e1e"; radius: 12
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 15 // 控制圆环与下方核心指示器的间距

                        CircleProgress {
                            Layout.preferredWidth: 90; Layout.preferredHeight: 90
                            value: backend.cpuTotal
                            centerText: (backend.cpuTotal * 100).toFixed(0) + "%"
                            subText: "CPU"
                            primaryColor: cpuColor(backend.cpuTotal)
                            Layout.alignment: Qt.AlignHCenter // 确保圆环自身居中
                        }
                        
                        // 核心指示器
                        Row {
                            Layout.alignment: Qt.AlignHCenter // 确保这行小点点居中
                            spacing: 4
                            Repeater {
                                model: backend.cpuCores
                                Rectangle {
                                    width: 8; height: 8; radius: 2
                                    color: cpuColor(modelData)
                                }
                            }
                        }
                    }
                    TapHandler { id: tapCpu; enabled: !cpuDetailsPopup.visible; onTapped: cpuDetailsPopup.open() }
                }

                // Memory Card
                Rectangle {
                    Layout.fillWidth: true; height: 160; color: "#1e1e1e"; radius: 12
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 15 // 增加圆环与文字间距

                        CircleProgress {
                            Layout.preferredWidth: 90; Layout.preferredHeight: 90
                            value: backend.memPercent
                            centerText: (backend.memPercent * 100).toFixed(0) + "%"
                            subText: "MEM"
                            primaryColor: memColor(backend.memPercent)
                            Layout.alignment: Qt.AlignHCenter
                        }
                        
                        Text { 
                            text: backend.memDetail
                            color: "#aaa"; font.pixelSize: 12 // 字体稍微调大一点点更清晰
                            Layout.alignment: Qt.AlignHCenter // 确保文字居中
                        }
                    }
                }
            }

            // --- Row 2: Disk & Battery ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 15

                // Disk Card (Root)
                Rectangle {
                    Layout.fillWidth: true; height: 160
                    color: tapDisk.pressed ? "#2a2a2a" : "#1e1e1e"; radius: 12
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 15 // 增加圆环与文字间距

                        CircleProgress {
                            Layout.preferredWidth: 90; Layout.preferredHeight: 90
                            value: backend.diskPercent
                            centerText: (backend.diskPercent * 100).toFixed(0) + "%"
                            subText: "DISK (/)"
                            primaryColor: diskColor(backend.diskPercent)
                            Layout.alignment: Qt.AlignHCenter
                        }
                        
                        Text { 
                            text: backend.diskRootUsage
                            color: "#aaa"; font.pixelSize: 12 
                            Layout.alignment: Qt.AlignHCenter // 确保文字居中
                        }
                    }
                    TapHandler { id: tapDisk; enabled: !diskPopup.visible; onTapped: diskPopup.open() }
                }

                // Battery Card
                Rectangle {
                    Layout.fillWidth: true; height: 160
                    color: tapBat.pressed ? "#2a2a2a" : "#1e1e1e"; radius: 12
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 15 // 增加圆环与文字间距

                        CircleProgress {
                            Layout.preferredWidth: 90; Layout.preferredHeight: 90
                            value: backend.batPercent / 100.0
                            centerText: backend.batPercent + "%"
                            subText: "BATTERY"
                            primaryColor: batteryColor(backend.batPercent, backend.batState)
                            Layout.alignment: Qt.AlignHCenter
                        }
                        
                        Text { 
                            text: backend.batState
                            color: "#aaa"; font.pixelSize: 12 
                            Layout.alignment: Qt.AlignHCenter // 确保文字居中
                        }
                    }
                    TapHandler { id: tapBat; enabled: !batPopup.visible; onTapped: batPopup.open() }
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