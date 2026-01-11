import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyDesktop.Backend 1.0

Window {
    id: window
    width: 360
    height: 720
    visible: true
    title: "Dashboard"
    color: "#121212"

    property bool historyExpanded: true

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
                focus: true
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
                            color: cpuColor(modelData)
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
                focus: true
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
                                // 尽量完整展示挂载点，优先留更多宽度且使用中间省略
                                Layout.fillWidth: true 
                                elide: Text.ElideMiddle
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
                                Layout.maximumWidth: parent.width * 0.8 // 放宽一点避免过度截断
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
                                color: diskColor(modelData.percent)
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
                focus: true
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

    Popup {
        id: netPopup
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.9
        height: parent.height * 0.7 // 网络信息可能比较长，给高一点
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        Overlay.modal: Rectangle { color: "#aa000000" }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 200 } }

        background: Rectangle {
            color: "#1e1e1e"
            radius: 15
            border.color: "#333333"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 15
            Item { height: 10; Layout.fillWidth: true }

            Text { 
                text: "Network Interfaces"
                color: "white"
                font.pixelSize: 20
                font.bold: true
                Layout.alignment: Qt.AlignHCenter 
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 20; Layout.rightMargin: 20
                clip: true
                spacing: 15
                model: backend.netInterfaces

                delegate: Rectangle {
                    width: ListView.view.width
                    // 自适应高度：根据 IP 数量撑开
                    height: contentCol.implicitHeight + 30
                    color: "#252525"
                    radius: 8
                    
                    ColumnLayout {
                        id: contentCol
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 8

                        // 1. 接口名 + 状态
                        RowLayout {
                            Layout.fillWidth: true
                            Text { 
                                text: modelData.name // wlan0
                                color: "#00E5FF" // 青色高亮
                                font.bold: true
                                font.pixelSize: 16
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                width: 40; height: 18; radius: 4
                                color: modelData.state === "UP" ? "#2E7D32" : "#C62828"
                                Text { 
                                    text: modelData.state
                                    anchors.centerIn: parent
                                    color: "white"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                        }

                        // 2. MAC 地址
                        Text {
                            visible: modelData.mac !== ""
                            text: "MAC: " + modelData.mac
                            color: "#888"
                            font.family: "Monospace"
                            font.pixelSize: 12
                        }
                        
                        // 分割线
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

                        // 3. IP 地址列表
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: modelData.ips // 这是一个 StringList
                                delegate: Text {
                                    text: modelData
                                    color: "#ddd"
                                    font.family: "Monospace"
                                    font.pixelSize: 13
                                    // 自动换行，防止 IPv6 太长
                                    wrapMode: Text.WrapAnywhere 
                                    Layout.fillWidth: true
                                }
                            }
                            // 如果没有 IP
                            Text {
                                visible: modelData.ips.length === 0
                                text: "No IP Address"
                                color: "#555"
                                font.italic: true
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }
            Item { height: 10; Layout.fillWidth: true }
        }
    }

    // ================= 页面导航 (StackView) =================
    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: homePage
        focus: true
        z: 0
        
        // 自定义页面切换动画 (推入/推出)
        pushEnter: Transition {
            PropertyAnimation { property: "x"; from: window.width; to: 0; duration: 250; easing.type: Easing.OutCubic }
        }
        pushExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: -window.width * 0.3; duration: 250; easing.type: Easing.OutCubic }
        }
        popEnter: Transition {
            PropertyAnimation { property: "x"; from: -window.width * 0.3; to: 0; duration: 250; easing.type: Easing.OutCubic }
        }
        popExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: window.width; duration: 250; easing.type: Easing.OutCubic }
        }
    }

    Drawer {
        id: drawer
        width: window.width * 0.65 // 稍微加宽一点，让大图标看起来更舒服
        height: window.height
        z: position > 0 ? 999 : 1      
        edge: Qt.LeftEdge 
        interactive: stackView.depth === 1 
        dragMargin: window.width * 0.2

        background: Rectangle {
            color: "#121212" // 整体背景加深
            layer.enabled: true
            // 右侧分割线/阴影
            Rectangle {
                anchors.right: parent.right
                width: 1; height: parent.height
                color: "#333"
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ==========================================
            // 1. 顶部 Logo 区域 (占据 45% 高度)
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: parent.height * 0.45
                
                // 渐变背景，提升质感
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#252525" }
                    GradientStop { position: 1.0; color: "#1a1a1a" }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 20

                    // 大 Logo
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 96; height: 96
                        color: "transparent"
                        
                        // 外部光晕效果 (可选)
                        Rectangle {
                            anchors.centerIn: parent
                            width: 80; height: 80
                            radius: 40
                            color: "#ffffff"
                            opacity: 0.05
                        }

                        IconImage {
                            anchors.centerIn: parent
                            source: "qrc:/MyDesktop/Backend/assets/logo.svg"
                            sourceSize: Qt.size(80, 80) // 放大图标
                            color: "white"
                        }
                    }

                    // 文字信息
                    ColumnLayout {
                        spacing: 5
                        Text {
                            text: "Orbital"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 22
                            font.letterSpacing: 2
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            // 分割线
            Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

            // ==========================================
            // 2. 底部功能按键区域 (剩余空间)
            // ==========================================
            ListView {
                id: menuList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                interactive: false // 禁止滚动，固定布局
                
                // 顶部留白
                header: Item { height: 20 }

                model: ListModel {
                    // Settings
                    ListElement { 
                        name: "Settings"; 
                        icon: "settings.svg"; 
                        action: "settings"; 
                        itemColor: "white" 
                    }
                    // Reset Desktop (Exit 42)
                    ListElement { 
                        name: "Reset Desktop"; 
                        icon: "refresh.svg";
                        action: "reset"; 
                        itemColor: "#12E7FF"
                    }
                    // Reboot
                    ListElement { 
                        name: "Reboot"; 
                        icon: "restart.svg";
                        action: "reboot"; 
                        itemColor: "#FF9800"
                    }
                    // Power Off
                    ListElement { 
                        name: "Shut Down"; 
                        icon: "power.svg";
                        action: "shutdown"; 
                        itemColor: "#FF5252"
                    }
                }

                delegate: ItemDelegate {
                    width: parent.width
                    height: 65
                    
                    background: Rectangle {
                        color: parent.down ? "#2a2a2a" : "transparent"
                        Rectangle {
                            width: 4; height: parent.height
                            color: model.itemColor
                            visible: parent.parent.down
                        }
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 30
                        anchors.rightMargin: 30
                        spacing: 20

                        // 图标
                        IconImage {
                            source: "qrc:/MyDesktop/Backend/assets/" + model.icon
                            sourceSize: Qt.size(24, 24)
                            color: model.itemColor // 图标颜色跟随定义
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // 文字
                        Text {
                            text: model.name
                            color: model.itemColor
                            font.pixelSize: 16
                            font.bold: true
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                    }

                    onClicked: {
                        // 稍微延迟关闭，让用户看到点击动画
                        drawer.close()
                        
                        if (model.action === "settings") {
                            stackView.push(settingsPage)
                        } 
                        else if (model.action === "reset") {
                            // 触发 Exit 42，配合 run.sh 重启
                            Qt.exit(42)
                        }
                        else if (model.action === "reboot") {
                            backend.systemCmd("reboot")
                        }
                        else if (model.action === "shutdown") {
                            backend.systemCmd("poweroff")
                        }
                    }
                }
            }
        }
    }

    // ================= MAIN UI =================
    Component {
        id: homePage
        Item {
            Rectangle { 
                anchors.fill: parent
                color: "#121212"
                z: -1 // 放在最底层作为背景
            }
            ColumnLayout {
                id: mainCol
                width: parent.width - 20
                x: 10
                y: 20
                spacing: 15

                Text { text: "Dashboard"; color: "white"; font.bold: true; font.pixelSize: 24; Layout.leftMargin: 5 }

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
                        TapHandler { 
                            id: tapCpu
                            enabled: !cpuDetailsPopup.visible
                            onTapped: {
                                if (!cpuDetailsPopup.visible) {
                                    cpuDetailsPopup.open()
                                }
                            }
                            // 防止多点触控干扰
                            acceptedButtons: Qt.LeftButton
                            // 设置适当的阈值
                            gesturePolicy: TapHandler.WithinBounds
                            // 处理取消事件
                            onCanceled: {
                            }
                        }
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
                        TapHandler { 
                            id: tapDisk
                            enabled: !diskPopup.visible
                            onTapped: {
                                if (!diskPopup.visible) {
                                    diskPopup.open()
                                }
                            }
                            // 防止多点触控干扰
                            acceptedButtons: Qt.LeftButton
                            // 设置适当的阈值
                            gesturePolicy: TapHandler.WithinBounds
                            // 处理取消事件
                            onCanceled: {
                                // 清理状态
                            }
                        }
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
                        TapHandler { 
                            id: tapBat
                            enabled: !batPopup.visible
                            onTapped: {
                                if (!batPopup.visible) {
                                    batPopup.open()
                                }
                            }
                            // 防止多点触控干扰
                            acceptedButtons: Qt.LeftButton
                            // 设置适当的阈值
                            gesturePolicy: TapHandler.WithinBounds
                            // 处理取消事件
                            onCanceled: {
                                // 清理状态
                            }
                        }
                    }
                }

                // --- Row 2.5: Real-time Network Status ---
                Rectangle {
                    Layout.fillWidth: true
                    height: 80
                    color: netTap.pressed ? "#2a2a2a" : "#1e1e1e"
                    radius: 12
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 10

                        // 图标/标题区域
                        ColumnLayout {
                            spacing: 2
                            Text { text: "Network"; color: "white"; font.bold: true; font.pixelSize: 16 }
                            Text { text: "Total Traffic"; color: "#666"; font.pixelSize: 12 }
                        }

                        Item { Layout.fillWidth: true } // 弹簧

                        // 下载速度
                        ColumnLayout {
                            spacing: 2
                            Layout.alignment: Qt.AlignRight
                            Text { 
                                text: "⬇ " + backend.netRxSpeed
                                color: "#00E676" // 绿色
                                font.family: "Monospace"
                                font.bold: true
                                font.pixelSize: 15
                                Layout.alignment: Qt.AlignRight
                            }
                            Text { text: "Download"; color: "#666"; font.pixelSize: 10; Layout.alignment: Qt.AlignRight }
                        }
                        
                        // 分割线
                        Rectangle { width: 1; height: 30; color: "#333" }

                        // 上传速度
                        ColumnLayout {
                            spacing: 2
                            Layout.alignment: Qt.AlignRight
                            Text { 
                                text: "⬆ " + backend.netTxSpeed
                                color: "#FF9800" // 橙色
                                font.family: "Monospace"
                                font.bold: true
                                font.pixelSize: 15
                                Layout.alignment: Qt.AlignRight
                                Layout.preferredWidth: 112
                                horizontalAlignment: Text.AlignRight
                            }
                            Text { text: "Upload"; color: "#666"; font.pixelSize: 10; Layout.alignment: Qt.AlignRight }
                        }
                    }
                    TapHandler {
                        id: netTap
                        enabled: !netPopup.visible
                        onTapped: netPopup.open()
                    }
                }

                // --- Row 3: 历史数据图表 ---
                Rectangle {
                    Layout.fillWidth: true
                    height: 500
                    color: "#1e1e1e"
                    radius: 12
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 15 
                        spacing: 5 // 减小间距，因为图表内部有 padding

                        Text {
                            text: "System History"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                            Layout.alignment: Qt.AlignVCenter
                            Layout.bottomMargin: 5
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 10

                            LineChart {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                
                                chartTitle: "CPU Usage"
                                
                                datasets: [
                                    { 
                                        label: "Total", 
                                        values: backend.cpuHistory, 
                                        color: "#FF5252" 
                                    }
                                ]
                                fixedMax: 100
                                suffix: "%"
                            }

                            Rectangle { 
                                Layout.fillWidth: true; height: 3; color: "#333333" 
                            }

                            LineChart {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                
                                chartTitle: "Memory Usage" // 【传入标题】
                                
                                datasets: [
                                    { 
                                        label: "RAM", 
                                        values: backend.memHistory, 
                                        color: "#2196F3" 
                                    }
                                ]
                                fixedMax: 100
                                suffix: "%"
                            }

                            Rectangle { 
                                Layout.fillWidth: true; height: 3; color: "#333333" 
                            }

                            // 3. Network
                            LineChart {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                chartTitle: "Network I/O"
                                
                                // 双曲线
                                datasets: [
                                    { label: "Down", values: backend.netRxHistory, color: "#00E676" },
                                    { label: "Up",   values: backend.netTxHistory, color: "#FF9800" }
                                ]
                                
                                // 开启自动缩放
                                fixedMax: -1 
                                // 历史记录统一用 KB/s，避免单位跳变导致图表乱跳
                                // (虽然主页卡片显示 MB/s，但折线图保持统一单位更稳定)
                                suffix: " KB/s" 
                            }
                        }
                    }
                }
                
                // Item { height: 5 }

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: implicitWidth
                    
                    // 使用 RowLayout 让图标和文字并排
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12
                        
                        IconImage {
                            source: "qrc:/MyDesktop/Backend/assets/logo.svg"
                            
                            color: "white" 
                            
                            sourceSize.width: 32
                            sourceSize.height: 32
                            
                            opacity: 0.85
                        }
                        
                        ColumnLayout {
                            spacing: 0
                            
                            Text {
                                text: appName
                                color: "#eeeeee" 
                                font.pixelSize: 15
                                font.bold: true
                                font.letterSpacing: 1.5
                                Layout.alignment: Qt.AlignLeft 
                            }
                            
                            Text {
                                text: "Build: " + appBuildHash
                                color: "#aaaaaa"
                                font.family: "Monospace"
                                font.pixelSize: 10
                                Layout.alignment: Qt.AlignLeft
                            }
                        }
                    }
                }

                // 底部安全距离
                // Item { height: 20 }
            }
        }
    }

    Component {
        id: settingsPage
        
        // 引用外部文件
        SettingsPage {
            // 1. 传入后端实例 (Window里定义的 backend id)
            sysMon: backend
            
            // 2. 响应返回信号
            onRequestBack: {
                stackView.pop()
            }
        }
    }
}