import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyDesktop.Backend 1.0

Page {
    id: wifiPage
    background: Rectangle { color: "#121212" }

    property var backend // 从外部传入 SystemMonitor 实例
    property string selectedSsid: ""

    // --- 密码输入弹窗 ---
    Popup {
        id: passPopup
        anchors.centerIn: parent
        width: parent.width * 0.85
        height: 220
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        y: Qt.inputMethod.visible ? (parent.height - height) / 2 - 100 : (parent.height - height) / 2

        background: Rectangle {
            color: "#1e1e1e"
            radius: 12
            border.color: "#333"
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 20
            spacing: 15

            Text { 
                text: "Connect to " + selectedSsid
                color: "white"; font.bold: true; font.pixelSize: 16
                Layout.alignment: Qt.AlignHCenter
            }

            TextField {
                id: passInput
                Layout.fillWidth: true
                placeholderText: "Password"
                echoMode: TextInput.Password
                color: "white"
                background: Rectangle { color: "#2d2d2d"; radius: 6 }
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData | Qt.ImhHiddenText
                onAccepted: connectBtn.clicked()
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Button {
                    text: "Cancel"
                    Layout.fillWidth: true
                    background: Rectangle { color: "#333"; radius: 6 }
                    contentItem: Text { text: parent.text; color: "white"; horizontalAlignment: Text.AlignHCenter }
                    onClicked: passPopup.close()
                }
                Button {
                    id: connectBtn
                    text: "Connect"
                    Layout.fillWidth: true
                    background: Rectangle { color: "#00E676"; radius: 6 }
                    contentItem: Text { text: parent.text; color: "#121212"; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                    onClicked: {
                        backend.connectToWifi(selectedSsid, passInput.text)
                        passPopup.close()
                        passInput.text = ""
                    }
                }
            }
        }
        onOpened: passInput.forceActiveFocus()
    }

    // --- 主界面 ---
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // 1. 标题栏
        Rectangle {
            Layout.fillWidth: true; height: 60; color: "#1e1e1e"
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 15
                ToolButton {
                    contentItem: Text { text: "◀"; color: "white"; font.pixelSize: 22 }
                    background: Rectangle { color: "transparent" }
                    onClicked: stackView.pop()
                }
                Text { text: "WLAN"; color: "white"; font.bold: true; font.pixelSize: 20 }
                Item { Layout.fillWidth: true }
                ToolButton {
                    contentItem: IconImage { source: "qrc:/MyDesktop/Backend/assets/refresh.svg"; sourceSize: Qt.size(20,20); color: "white" }
                    background: Rectangle { color: parent.pressed ? "#333" : "transparent"; radius: 4 }
                    onClicked: backend.scanWifiNetworks()
                    visible: backend.wifiEnabled
                }
            }
        }

        // 2. 开关区域 (固定高度，不动)
        Rectangle {
            Layout.fillWidth: true; height: 60; color: "#121212"
            z: 2 // 稍微提高层级
            RowLayout {
                anchors.fill: parent; anchors.margins: 20
                Text { text: "Use WLAN"; color: "white"; font.pixelSize: 16; Layout.fillWidth: true }
                Switch {
                    checked: backend.wifiEnabled
                    onToggled: backend.wifiEnabled = checked
                    indicator: Rectangle {
                        implicitWidth: 48; implicitHeight: 26; radius: 13; color: parent.checked ? "#00E676" : "#333"
                        Rectangle { x: parent.parent.checked ? parent.width - width - 2 : 2; y: 2; width: 22; height: 22; radius: 11; color: "white"; Behavior on x { NumberAnimation { duration: 200 } } }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

        // 3. 内容容器 (占满剩余空间)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true 

            // --- 状态 A: WiFi 已关闭 (居中显示) ---
            ColumnLayout {
                anchors.centerIn: parent
                visible: !backend.wifiEnabled
                spacing: 15
                
                // 圆形背景图标
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 80; height: 80
                    color: "#222"
                    radius: 40
                    IconImage {
                        anchors.centerIn: parent
                        source: "qrc:/MyDesktop/Backend/assets/wifi-off.svg" 
                        sourceSize: Qt.size(40, 40)
                        color: "#666"
                    }
                }
                Text {
                    text: "WLAN is off"
                    color: "#666"
                    font.pixelSize: 16
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            // --- 状态 B: WiFi 列表 ---
            ListView {
                anchors.fill: parent
                clip: true
                model: backend.wifiList
                visible: backend.wifiEnabled

                delegate: ItemDelegate {
                    width: parent.width
                    height: 64
                    
                    background: Rectangle { color: parent.down ? "#2a2a2a" : "transparent" }

                    contentItem: RowLayout {
                        spacing: 15
                        anchors.leftMargin: 20; anchors.rightMargin: 20

                        // [固定宽度的容器] 1. 信号图标
                        // 这样即使换图标，右边的文字也不会跳动
                        Item {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter

                            // 计算信号等级 (0-4)
                            // nmcli 返回的 level 是 unicode 字符串，如 "▂▄▆_"
                            property int signalLevel: {
                                var s = modelData.level;
                                if (s.indexOf("█") !== -1) return 4;
                                if (s.indexOf("▆") !== -1) return 3;
                                if (s.indexOf("▄") !== -1) return 2;
                                if (s.indexOf("▂") !== -1) return 1;
                                return 0;
                            }

                            IconImage {
                                anchors.centerIn: parent
                                // 动态拼接文件名: wifi_0.svg ... wifi_4.svg
                                source: "qrc:/MyDesktop/Backend/assets/wifi_" + parent.signalLevel + ".svg"
                                sourceSize: Qt.size(24, 24)
                                // 已连接显示绿色，否则白色
                                color: modelData.connected ? "#00E676" : "white"
                            }
                        }

                        // [自适应] 2. 名称与状态
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Layout.alignment: Qt.AlignVCenter
                            
                            Text { 
                                text: modelData.ssid
                                color: modelData.connected ? "#00E676" : "white"
                                font.bold: true
                                font.pixelSize: 16
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                id: statusText
                                color: "#888"
                                font.pixelSize: 12
                                Layout.fillWidth: true
                                
                                text: {
                                    if (modelData.connected) {
                                        return "Connected";
                                    } else {
                                        // 如果 securityType 为空，显示 Open
                                        // 否则显示具体的类型 (如 WPA2)
                                        return modelData.securityType === "" ? "Open" : modelData.securityType
                                    }
                                }
                            }
                        }

                        // [固定位置] 3. 右侧状态图标 (锁/勾)
                        Item {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            
                            IconImage {
                                anchors.centerIn: parent
                                source: modelData.connected ? "qrc:/MyDesktop/Backend/assets/check.svg" : (modelData.secured ? "qrc:/MyDesktop/Backend/assets/lock.svg" : "")
                                sourceSize: Qt.size(18, 18)
                                color: modelData.connected ? "#00E676" : "#666"
                            }
                        }
                    }

                    onClicked: {
                        if (modelData.connected) return;
                        selectedSsid = modelData.ssid
                        if (modelData.secured) {
                            passPopup.open()
                        } else {
                            backend.connectToWifi(selectedSsid, "")
                        }
                    }
                }
                
                Text {
                    visible: parent.count === 0 && backend.wifiEnabled
                    text: "Scanning..."
                    color: "#666"
                    anchors.centerIn: parent
                    font.pixelSize: 16
                }
            }
        }
    }

    Component.onCompleted: {
        if (backend.wifiEnabled) backend.scanWifiNetworks()
    }
}