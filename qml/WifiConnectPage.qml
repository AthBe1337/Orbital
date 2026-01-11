import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyDesktop.Backend 1.0

Page {
    id: connectPage
    background: Rectangle { color: "#121212" }

    property var backend
    property var wifiData: ({}) 

    // 内部状态
    readonly property bool isConnected: wifiData.connected === true
    readonly property bool isSaved: wifiData.isSaved === true && !isConnected
    readonly property bool isNew: !isSaved && !isConnected
    // 密码可见性状态
    property bool showPassword: false

    // --- 顶部导航栏 ---
    header: Rectangle {
        height: 52
        color: "#1e1e1e"
        z: 10 
        
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
                background: Rectangle { color: parent.pressed ? "#333" : "transparent" }
                onClicked: stackView.pop()
            }

            Text {
                text: isConnected ? "Details" : "Connect" // 标题动态变化
                color: "white"; font.bold: true; font.pixelSize: 25
                Layout.leftMargin: 5
            }
            Item { Layout.fillWidth: true }
        }
    }

    ScrollView {
        id: scrollView
        anchors.top: parent.top
        anchors.bottom: parent.bottom // 不再避让键盘，占满全屏
        anchors.left: parent.left
        anchors.right: parent.right
        
        // 只有当内容超出屏幕时才允许滚动
        contentHeight: mainCol.implicitHeight
        clip: true

        Item {
            width: scrollView.availableWidth
            
            height: Math.max(scrollView.availableHeight, mainCol.implicitHeight)

            ColumnLayout {
                id: mainCol
                width: scrollView.availableWidth
                spacing: 20
                
                // 顶部弹性空间，让内容往下压，居中显示
                Item { 
                    Layout.fillHeight: true 
                    Layout.preferredHeight: 1 // 权重 1
                    Layout.minimumHeight: 40 
                }

                // --- 顶部图标和名称 ---
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 15

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 80; height: 80; radius: 40
                        color: isConnected ? "#2979FF33" : "#333"
                        IconImage {
                            anchors.centerIn: parent
                            source: "qrc:/MyDesktop/Backend/assets/wifi.svg"
                            sourceSize: Qt.size(40,40)
                            color: isConnected ? "#2979FF" : "white"
                        }
                    }

                    Text {
                        text: wifiData.ssid || "Unknown SSID"
                        color: "white"; font.bold: true; font.pixelSize: 22
                        Layout.alignment: Qt.AlignHCenter
                        elide: Text.ElideRight // 防止超长 SSID 撑破布局
                        Layout.maximumWidth: connectPage.width * 0.8
                    }
                    
                    Text {
                        text: {
                            if (isConnected) return "Connected";
                            if (isSaved) return "Saved";
                            return wifiData.securityType ? wifiData.securityType : "Open";
                        }
                        color: isConnected ? "#2979FF" : "#888"
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignHCenter
                    }
                }

                // --- 布局 A: 已连接 ---
                ColumnLayout {
                    visible: isConnected
                    Layout.fillWidth: true
                    Layout.leftMargin: 40; Layout.rightMargin: 40
                    spacing: 25 // 加大间距

                    // 分割线
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

                    // 1. IP
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 5
                        Text { text: "IP Address"; color: "#888"; font.pixelSize: 14; Layout.alignment: Qt.AlignHCenter }
                        Text { 
                            text: (backend.currentWifiDetails && backend.currentWifiDetails.ip) || "--"
                            color: "white"; font.bold: true; font.pixelSize: 18; Layout.alignment: Qt.AlignHCenter 
                        }
                    }

                    // 2. MAC
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 5
                        Text { text: "MAC Address"; color: "#888"; font.pixelSize: 14; Layout.alignment: Qt.AlignHCenter }
                        Text { 
                            text: (backend.currentWifiDetails && backend.currentWifiDetails.mac) || "--"
                            color: "white"; font.bold: true; font.pixelSize: 18; Layout.alignment: Qt.AlignHCenter 
                        }
                    }

                    // 3. 信号
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 5
                        Text { text: "Signal Strength"; color: "#888"; font.pixelSize: 14; Layout.alignment: Qt.AlignHCenter }
                        Text { 
                            text: (wifiData.level || "0") + "%"
                            color: "white"; font.bold: true; font.pixelSize: 18; Layout.alignment: Qt.AlignHCenter 
                        }
                    }

                    // 分割线
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

                    // 4. 断开连接按钮
                    Button {
                        z: 20
                        text: "Disconnect"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 50
                        Layout.topMargin: 10
                        
                        background: Rectangle {
                            color: parent.down ? "#b71c1c" : "#332a2a" // 暗红色背景
                            radius: 8
                            border.color: "#FF5252"
                            border.width: 1
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            color: "#FF5252" // 红色文字
                            font.bold: true
                            font.pixelSize: 16
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        
                        onClicked: {
                            backend.disconnectFromWifi(wifiData.ssid)
                            stackView.pop() // 断开后返回列表页
                        }
                    }
                }

                // --- 布局 B: 已保存 ---
                ColumnLayout {
                    visible: isSaved
                    Layout.fillWidth: true; Layout.margins: 40
                    spacing: 20
                    RowLayout {
                        z: 20
                        Layout.fillWidth: true
                        Text { text: "Auto Connect"; color: "white"; font.pixelSize: 16; Layout.fillWidth: true }
                        Switch {
                            checked: wifiData.autoConnect === true
                            onToggled: backend.setAutoConnect(wifiData.ssid, checked)
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }
                    RowLayout {
                        z: 20
                        Layout.fillWidth: true; spacing: 15
                        Button {
                            text: "Forget"
                            Layout.fillWidth: true; Layout.preferredHeight: 45
                            background: Rectangle { color: "#332a2a"; radius: 8 }
                            contentItem: Text { text: parent.text; color: "#FF5252"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: { backend.forgetNetwork(wifiData.ssid); stackView.pop() }
                        }
                        Button {
                            text: "Connect"
                            Layout.fillWidth: true; Layout.preferredHeight: 45
                            background: Rectangle { color: "#2979FF"; radius: 8 }
                            contentItem: Text { text: parent.text; color: "white"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: { backend.connectToWifi(wifiData.ssid, ""); stackView.pop() }
                        }
                    }
                }

                // --- 布局 C: 新网络 (输入密码) ---
                ColumnLayout {
                    visible: isNew
                    Layout.fillWidth: true; Layout.margins: 30
                    spacing: 20

                    Rectangle {
                        z: 20
                        Layout.fillWidth: true; height: 50
                        color: "#222"; radius: 8
                        border.color: passInput.activeFocus ? "#2979FF" : "#333"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0

                            // 输入区域
                            TextInput {
                                id: passInput
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.leftMargin: 15
                                z: 90
                                focus: false
                                
                                verticalAlignment: Text.AlignVCenter
                                color: "white"; font.pixelSize: 18
                                
                                // 3. 限制显示范围，防止文字溢出
                                clip: true 
                                
                                // 4. 显隐控制
                                echoMode: showPassword ? TextInput.Normal : TextInput.Password
                                passwordCharacter: "•"

                                Text {
                                    text: "Password"; color: "#555"; font.pixelSize: 16
                                    visible: !parent.text && !parent.activeFocus
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                TapHandler {
                                    onTapped: {
                                        passInput.forceActiveFocus()
                                        customKeyboard.target = passInput
                                        customKeyboard.visible = true
                                    }
                                }

                                onAccepted: confirmConnect()
                            }

                            // 4. 右侧眼睛按钮
                            Item {
                                Layout.preferredWidth: 40; Layout.fillHeight: true
                                visible: passInput.text.length > 0 // 有字时才显示
                                z: 9999

                                IconImage {
                                    anchors.centerIn: parent
                                    source: showPassword ? "qrc:/MyDesktop/Backend/assets/eye-off.svg" : "qrc:/MyDesktop/Backend/assets/eye.svg"
                                    sourceSize: Qt.size(24, 24)
                                    color: "#888"
                                }
                                
                                TapHandler {
                                    onTapped: {
                                        showPassword = !showPassword
                                        // 切换模式后，强制保持焦点，防止键盘收起
                                        passInput.forceActiveFocus()
                                        customKeyboard.target = passInput
                                        customKeyboard.visible = true
                                    }
                                }
                            }
                            
                            // 右边距
                            Item { Layout.preferredWidth: 10 }
                        }
                    }

                    Button {
                        z: 20
                        text: "Connect"
                        Layout.fillWidth: true; Layout.preferredHeight: 45
                        background: Rectangle { color: "#2979FF"; radius: 8 }
                        contentItem: Text { text: parent.text; color: "white"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: confirmConnect()
                    }
                }
            }
        }
    }

    // ==========================================
    // 底部键盘 (覆盖在内容之上)
    // ==========================================
    CustomKeyboard {
        id: customKeyboard
        width: parent.width
        z: 999 // 确保在最上层
        
        visible: false 

        onEnterClicked: confirmConnect()
    }

    // --- 逻辑函数 ---
    function confirmConnect() {
        if (isNew) {
            backend.connectToWifi(wifiData.ssid, passInput.text)
            stackView.pop()
        }
    }
    
    Component.onCompleted: {
        if (isNew && wifiData.secured) {
            // 自动聚焦
            passInput.forceActiveFocus()
            customKeyboard.visible = true
            customKeyboard.target = passInput
        }
    }
}