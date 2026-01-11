import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyDesktop.Backend 1.0

Page {
    id: wifiPage
    background: Rectangle { color: "#121212" }

    property var backend
    
    // --- 内部 UI 状态 ---
    property bool isScanning: false
    property bool isToggling: false
    property string toastMessage: ""

    // 监听后端信号
    Connections {
        target: backend
        function onWifiListChanged() { isScanning = false }
        function onWifiEnabledChanged() { isToggling = false }
        function onWifiOperationResult(op, success, msg) {
            if (op === "toggle") isToggling = false
            if (!success) showToast("Error: " + msg)
            else if (op === "forget") showToast("Network forgotten")
            else if (op === "connect") showToast("Connected successfully")
        }
    }

    function showToast(msg) {
        toastMessage = msg
        toastTimer.restart()
    }

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
            z: 10
            
            RowLayout {
                anchors.fill: parent
                spacing: 0
                anchors.leftMargin: 10
                anchors.rightMargin: 15

                // 返回按钮
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

                // 标题文字 (25px Bold)
                Text {
                    text: "WLAN"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 25
                    Layout.leftMargin: 5
                }
                
                // 弹簧撑开中间
                Item { Layout.fillWidth: true }
                
                // 刷新按钮
                ToolButton {
                    visible: backend.wifiEnabled
                    Layout.preferredWidth: 52 
                    Layout.fillHeight: true 
                    
                    background: Rectangle { color: parent.pressed ? "#333" : "transparent"; radius: 4 }
                    
                    contentItem: IconImage {
                        id: refreshIcon
                        anchors.centerIn: parent
                        source: "qrc:/MyDesktop/Backend/assets/refresh.svg"
                        sourceSize: Qt.size(28,28)
                        color: "white"
                        
                        RotationAnimator on rotation {
                            running: isScanning
                            from: 0; to: 360
                            duration: 1000
                            loops: Animation.Infinite
                            
                            onRunningChanged: { 
                                if (!running) refreshIcon.rotation = 0 
                            }
                        }
                    }

                    onClicked: {
                        isScanning = true
                        backend.scanWifiNetworks()
                    }
                }
            }
        }

        // ============================================================
        // 开关区域
        // ============================================================
        Rectangle {
            Layout.fillWidth: true; height: 72 
            color: "#121212"
            z: 2
            
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20
                
                // 左侧文字
                Text { 
                    text: "Enable WLAN"
                    color: "white"; font.pixelSize: 18
                }
                
                Item { Layout.fillWidth: true }
                
                // 右侧开关容器
                Item {
                    Layout.preferredWidth: 50; Layout.preferredHeight: 30
                    
                    // 正常状态显示开关
                    Switch {
                        id: masterSwitch
                        anchors.centerIn: parent
                        visible: !isToggling
                        checked: backend.wifiEnabled
                        
                        topPadding: 0
                        bottomPadding: 0
                        leftPadding: 0
                        rightPadding: 0
                        
                        onClicked: {
                            isToggling = true
                            backend.wifiEnabled = checked
                        }
                        
                        indicator: Rectangle {
                            implicitWidth: 48; implicitHeight: 26; radius: 13
                            color: masterSwitch.checked ? "#26A8FF" : "#333"
                            
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Rectangle { 
                                x: masterSwitch.checked ? parent.width - width - 2 : 2; y: 2
                                width: 22; height: 22; radius: 11
                                color: "white"
                                Behavior on x { NumberAnimation { duration: 200 } } 
                            }
                        }
                    }
                    
                    // 切换中显示小菊花 (位置与 Switch 重叠)
                    Rectangle {
                        anchors.centerIn: parent
                        width: 22; height: 22; radius: 11
                        color: "transparent"
                        border.width: 2; border.color: "#888"
                        visible: isToggling
                        
                        // 部分透明造成旋转视觉效果
                        Rectangle { width: 10; height: 10; x: 10; y: 0; color: "#121212" } 
                        
                        RotationAnimator on rotation {
                            running: parent.visible
                            from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

        // ============================================================
        // 内容容器
        // ============================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true 

            // WiFi 已关闭提示
            ColumnLayout {
                anchors.centerIn: parent
                visible: !backend.wifiEnabled && !isToggling
                spacing: 15
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 80; height: 80; color: "#222"; radius: 40
                    IconImage { anchors.centerIn: parent; source: "qrc:/MyDesktop/Backend/assets/wifi-off.svg"; sourceSize: Qt.size(40, 40); color: "#666" }
                }
                Text { text: "WLAN is off"; color: "#666"; font.pixelSize: 16; Layout.alignment: Qt.AlignHCenter }
            }

            // WiFi 列表
            ListView {
                id: wifiListView
                anchors.fill: parent
                clip: true
                visible: backend.wifiEnabled
                model: backend.wifiList

                Text {
                    visible: parent.count === 0 && !isScanning
                    text: "No networks found"; color: "#666"; anchors.centerIn: parent; font.pixelSize: 16
                }

                delegate: Column {
                    width: ListView.view.width
                    property string currentCategory: getCategory(modelData)
                    property string prevCategory: index > 0 ? getCategory(backend.wifiList[index - 1]) : ""
                    property bool showHeader: index === 0 || currentCategory !== prevCategory

                    function getCategory(data) {
                        if (!data) return ""
                        if (data.connected) return "Current Network"
                        if (data.isSaved) return "Saved Networks"
                        return "Available Networks"
                    }

                    // 分组标题
                    Item {
                        width: parent.width; height: 40; visible: showHeader
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 20
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                            text: currentCategory; color: "#26A8FF"; font.bold: true; font.pixelSize: 14
                        }
                    }

                    // 列表项
                    ItemDelegate {
                        width: parent.width; height: 64
                        background: Rectangle { color: parent.down ? "#2a2a2a" : "transparent" }
                        contentItem: RowLayout {
                            spacing: 15; anchors.leftMargin: 20; anchors.rightMargin: 20
                            
                            // 图标
                            Item {
                                Layout.preferredWidth: 24; Layout.preferredHeight: 24; Layout.alignment: Qt.AlignVCenter
                                property int signalLevel: {
                                    var s = Number(modelData.level);
                                    if (isNaN(s)) return 0;
                                    return s >= 75 ? 3 : (s >= 50 ? 2 : (s >= 25 ? 1 : 0));
                                }
                                IconImage {
                                    anchors.centerIn: parent
                                    source: "qrc:/MyDesktop/Backend/assets/wifi_" + parent.signalLevel + ".svg"
                                    sourceSize: Qt.size(24, 24)
                                    color: modelData.connected ? "#26A8FF" : "white"
                                }
                            }
                            
                            // 文字
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4; Layout.alignment: Qt.AlignVCenter
                                Text { 
                                    text: modelData.ssid; color: modelData.connected ? "#26A8FF" : "white"
                                    font.bold: true; font.pixelSize: 16; elide: Text.ElideRight; Layout.fillWidth: true
                                }
                                Text {
                                    color: "#888"; font.pixelSize: 12; Layout.fillWidth: true
                                    text: modelData.connected ? "Connected" : (modelData.isSaved ? "Saved" : (modelData.securityType === "" ? "Open" : modelData.securityType))
                                }
                            }
                            
                            // 状态图标
                            Item {
                                Layout.preferredWidth: 24; Layout.preferredHeight: 24; Layout.alignment: Qt.AlignVCenter
                                IconImage {
                                    anchors.centerIn: parent
                                    source: modelData.connected ? "qrc:/MyDesktop/Backend/assets/check.svg" : (modelData.secured ? "qrc:/MyDesktop/Backend/assets/lock.svg" : "")
                                    sourceSize: Qt.size(18, 18)
                                    color: modelData.connected ? "#26A8FF" : "#666"
                                }
                            }
                        }
                        onClicked: stackView.push("qrc:/MyDesktop/Backend/qml/WifiConnectPage.qml", { "backend": backend, "wifiData": modelData })
                    }
                }
            }
        }
    }

    // Toast
    Rectangle {
        id: toast
        color: "#333"; radius: 8
        width: Math.min(parent.width - 40, toastText.implicitWidth + 40); height: toastText.implicitHeight + 20
        anchors.bottom: parent.bottom; anchors.bottomMargin: 30; anchors.horizontalCenter: parent.horizontalCenter
        opacity: 0; visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
        Text { id: toastText; text: toastMessage; color: "white"; anchors.centerIn: parent; wrapMode: Text.Wrap; font.pixelSize: 14 }
        Timer { id: toastTimer; interval: 3000; onTriggered: toast.opacity = 0; onRunningChanged: if (running) toast.opacity = 1 }
    }
}