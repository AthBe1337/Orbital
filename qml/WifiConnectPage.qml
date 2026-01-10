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

    // ===============================================================
    // 1. 全局点击监听 (点击空白处收起键盘)
    // ===============================================================
    MouseArea {
        anchors.fill: parent
        z: 0 // 最底层
        onClicked: {
            // 使输入框失去焦点
            passInput.focus = false
            // 隐藏键盘
            customKeyboard.visible = false
        }
    }

    // --- 顶部导航栏 ---
    header: Rectangle {
        height: 52
        color: "#1e1e1e"
        z: 10 // 保证在滚动视图之上
        
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
                text: "Connect"
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

        ColumnLayout {
            id: mainCol
            width: scrollView.availableWidth
            spacing: 20
            
            // 【优化】顶部弹性空间，让内容往下压，居中显示
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
            GridLayout {
                visible: isConnected
                columns: 2
                Layout.fillWidth: true; Layout.margins: 40
                rowSpacing: 15; columnSpacing: 20

                Text { text: "IP Address"; color: "#666"; font.pixelSize: 14 }
                Text { text: (backend.currentWifiDetails && backend.currentWifiDetails.ip) || "--"; color: "white"; font.pixelSize: 14; Layout.alignment: Qt.AlignRight }
                
                Rectangle { Layout.columnSpan: 2; Layout.fillWidth: true; height: 1; color: "#333" }

                Text { text: "MAC Address"; color: "#666"; font.pixelSize: 14 }
                Text { text: (backend.currentWifiDetails && backend.currentWifiDetails.mac) || "--"; color: "white"; font.pixelSize: 14; Layout.alignment: Qt.AlignRight }
                
                Rectangle { Layout.columnSpan: 2; Layout.fillWidth: true; height: 1; color: "#333" }
                
                Text { text: "Signal Strength"; color: "#666"; font.pixelSize: 14 }
                Text { text: wifiData.level || "0"; color: "white"; font.pixelSize: 14; Layout.alignment: Qt.AlignRight }
            }

            // --- 布局 B: 已保存 ---
            ColumnLayout {
                visible: isSaved
                Layout.fillWidth: true; Layout.margins: 40
                spacing: 20
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Auto Connect"; color: "white"; font.pixelSize: 16; Layout.fillWidth: true }
                    Switch {
                        checked: wifiData.autoConnect === true
                        onToggled: backend.setAutoConnect(wifiData.ssid, checked)
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }
                RowLayout {
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

                // 4. 重构后的密码输入框
                Rectangle {
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

                            onActiveFocusChanged: {
                                if (activeFocus) {
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
                            
                            IconImage {
                                anchors.centerIn: parent
                                source: showPassword ? "qrc:/MyDesktop/Backend/assets/eye.svg" : "qrc:/MyDesktop/Backend/assets/eye-off.svg"
                                sourceSize: Qt.size(24, 24)
                                color: "#888"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    showPassword = !showPassword
                                    // 切换模式后，强制保持焦点，防止键盘收起
                                    passInput.forceActiveFocus()
                                }
                            }
                        }
                        
                        // 右边距
                        Item { Layout.preferredWidth: 10 }
                    }
                }

                Button {
                    text: "Connect"
                    Layout.fillWidth: true; Layout.preferredHeight: 45
                    background: Rectangle { color: "#2979FF"; radius: 8 }
                    contentItem: Text { text: parent.text; color: "white"; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: confirmConnect()
                }
            }

            // 【优化】底部弹性空间 (权重比顶部大，视觉中心偏上)
            Item { 
                Layout.fillHeight: true 
                Layout.preferredHeight: 2 // 权重 2
                Layout.minimumHeight: 60 
            }
        }
    }

    // ==========================================
    // 底部键盘 (覆盖在内容之上)
    // ==========================================
    CustomKeyboard {
        id: customKeyboard
        width: parent.width
        z: 100 // 确保在最上层
        
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
        }
    }
}