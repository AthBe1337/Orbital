import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: keyboard
    width: parent ? parent.width : 720
    height: terminalMode ? 320 : 270 // 终端模式稍高
    color: "#1C1E26" // 深空灰背景
    radius: 0 // 贴底无需圆角，或仅上方圆角

    // 这是一个滑动弹出的面板，默认在屏幕底部下方
    y: visible ? parent.height - height : parent.height

    // --- 公共接口 ---
    property var target: null // 当前控制的输入框
    property bool terminalMode: false // 切换 1:普通 / 2:终端 模式
    property bool showPreview: false // 是否显示按键气泡预览

    signal enterClicked() // 回车键被点击信号
    signal hideClicked()  // 收起键盘信号

    // --- 内部状态 ---
    property bool isUpper: false
    property bool isSym: false // 符号页
    property bool isCtrl: false // Terminal Ctrl状态
    property bool isAlt: false  // Terminal Alt状态

    // 动画
    Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

    // 防止点击穿透到下面
    MouseArea { 
        anchors.fill: parent
        preventStealing: true 
        onPressed: (mouse)=> mouse.accepted = true 
    }

    // --- 键盘布局数据 ---
    readonly property var row1: ["q","w","e","r","t","y","u","i","o","p"]
    readonly property var row2: ["a","s","d","f","g","h","j","k","l"]
    readonly property var row3: ["z","x","c","v","b","n","m"]
    readonly property var sym1: ["1","2","3","4","5","6","7","8","9","0"]
    readonly property var sym2: ["!","@","#","$","%","^","&","*","(",")"]
    readonly property var sym3: ["~","-","+","=","_","[","]","{","}","\\"]
    readonly property var sym4: [":",";","\"","'","<",">",",",".","/","?"]

    // 终端专用行
    readonly property var termRow: ["Esc", "Tab", "Ctrl", "Alt", "←", "↑", "↓", "→"]

    ColumnLayout {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 4
        spacing: 4

        // ============================
        // 0. 终端功能键行 (仅 terminalMode 显示)
        // ============================
        RowLayout {
            visible: terminalMode
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            spacing: 4

            Repeater {
                model: termRow
                delegate: KeyButton {
                    text: modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // 高亮 Ctrl/Alt 状态
                    highlighted: (text === "Ctrl" && isCtrl) || (text === "Alt" && isAlt)

                    onClicked: {
                        if (text === "Ctrl") isCtrl = !isCtrl
                        else if (text === "Alt") isAlt = !isAlt
                        else if (text === "Esc") handleSpecialKey(Qt.Key_Escape)
                        else if (text === "Tab") insertText("\t")
                        else if (text === "←") moveCursor(-1)
                        else if (text === "→") moveCursor(1)
                        else if (text === "↑") { /* Shell History Up */ }
                        else if (text === "↓") { /* Shell History Down */ }
                    }
                }
            }
        }

        // ============================
        // 1. 第一行 (数字/符号 或 QWERTY)
        // ============================
        RowLayout {
            Layout.fillWidth: true; Layout.preferredWidth: 1
            spacing: 4
            Repeater {
                model: isSym ? sym1 : row1
                delegate: CharKey { text: getKeyLabel(modelData) }
            }
        }

        // ============================
        // 2. 第二行
        // ============================
        RowLayout {
            Layout.fillWidth: true; Layout.preferredWidth: 1
            Layout.leftMargin: width * 0.05; Layout.rightMargin: width * 0.05 // 缩进模拟真实键盘
            spacing: 4
            Repeater {
                model: isSym ? sym3 : row2
                delegate: CharKey { text: getKeyLabel(modelData) }
            }
        }

        // ============================
        // 3. 第三行 (Shift + 字母 + Backspace)
        // ============================
        RowLayout {
            Layout.fillWidth: true; Layout.preferredWidth: 1
            spacing: 4

            // Shift / Caps
            KeyButton {
                iconSource: isUpper ? "qrc:/MyDesktop/Backend/assets/shift-filled.svg" : "qrc:/MyDesktop/Backend/assets/shift.svg"
                text: isSym ? "#+=" : "" // 符号页切换第二页符号
                Layout.fillWidth: true; Layout.preferredWidth: 1.5
                Layout.fillHeight: true
                highlighted: isUpper
                onClicked: {
                    if (isSym) {
                        // 符号页暂未实现第二页，可留空或切换 sym2
                    } else {
                        isUpper = !isUpper
                    }
                }
            }

            // 字母区
            Repeater {
                model: isSym ? sym4 : row3
                delegate: CharKey { text: getKeyLabel(modelData) }
            }

            // Backspace
            KeyButton {
                iconSource: "qrc:/MyDesktop/Backend/assets/backspace.svg"
                text: "←"
                Layout.fillWidth: true; Layout.preferredWidth: 1.5
                Layout.fillHeight: true
                repeat: true 

                onClicked: {
                    if (target && target.text.length > 0) {
                        var p = target.cursorPosition
                        if (p > 0) {
                            target.remove(p - 1, p)
                        }
                    }
                }
            }
        }

        // ============================
        // 4. 第四行 (功能区 + 空格)
        // ============================
        RowLayout {
            Layout.fillWidth: true; Layout.preferredWidth: 1
            spacing: 4

            // 切换符号/字母
            KeyButton {
                text: isSym ? "ABC" : "?123"
                Layout.fillWidth: true; Layout.preferredWidth: 1.5
                Layout.fillHeight: true
                onClicked: { isSym = !isSym }
            }

            // 逗号 (快捷键)
            KeyButton {
                text: ","
                Layout.fillWidth: true; Layout.preferredWidth: 1
                Layout.fillHeight: true
                onClicked: insertText(",")
            }

            // Space
            KeyButton {
                text: "Space"
                Layout.fillWidth: true; Layout.preferredWidth: 4
                Layout.fillHeight: true
                onClicked: insertText(" ")
            }

            // 句号 (快捷键)
            KeyButton {
                text: "."
                Layout.fillWidth: true; Layout.preferredWidth: 1
                Layout.fillHeight: true
                onClicked: insertText(".")
            }

            // Hide / Enter
            KeyButton {
                text: terminalMode ? "Enter" : "Done"
                color: "#2979FF" // 蓝色高亮
                textColor: "white"
                Layout.fillWidth: true; Layout.preferredWidth: 1.5
                Layout.fillHeight: true
                onClicked: {
                    enterClicked() // 发出信号
                    if (!terminalMode) {
                        keyboard.visible = false
                        target.focus = false
                    } else {
                        insertText("\n") // 终端模式换行
                    }
                }
            }
        }
    }

    // --- 辅助组件：按键按钮 ---
    component KeyButton : Rectangle {
        id: keyBtnRoot
        
        property string text: ""
        property string iconSource: ""
        property color textColor: "white"
        property bool highlighted: false
        property bool repeat: false 
        
        signal clicked()
        
        // 视觉反馈：直接绑定 TapHandler 的 pressed 状态
        // TapHandler 的状态管理由 C++ 底层处理，极难卡死
        color: highlighted ? "#444" : (inputHandler.pressed ? "#666" : "#2D2D2D")
        radius: 6

        // 文本
        Text {
            anchors.centerIn: parent
            text: parent.text; color: parent.textColor
            font.pixelSize: 18; visible: parent.iconSource === ""
        }
        IconImage {
            anchors.centerIn: parent
            source: parent.iconSource; sourceSize: Qt.size(24, 24)
            color: parent.textColor; visible: parent.iconSource !== ""
        }

        // 【核心修改】使用 TapHandler 代替 MouseArea
        TapHandler {
            id: inputHandler
            
            // 允许在按键范围内轻微滑动，只要松开时还在范围内就算点击
            // 这对触摸屏非常友好，容错率高
            gesturePolicy: TapHandler.ReleaseWithinBounds

            // 监听按下状态变化
            onPressedChanged: {
                if (pressed) {
                    // 1. 按下瞬间：立即触发
                    triggerKey()
                    
                    // 2. 如果是连发键(如删除)，启动定时器
                    if (keyBtnRoot.repeat) {
                        repeatTimer.restart()
                    }
                } else {
                    // 3. 抬起瞬间：停止连发
                    repeatTimer.stop()
                }
            }
        }

        // 【连发定时器】(逻辑不变)
        Timer {
            id: repeatTimer
            interval: 120 
            repeat: true
            onTriggered: triggerKey()
        }

        // 【焦点归还定时器】(逻辑不变)
        // 依然需要这个异步逻辑来防止焦点丢失
        Timer {
            id: focusRestorer
            interval: 1
            repeat: false
            onTriggered: {
                if (keyboard.target) {
                    keyboard.target.forceActiveFocus()
                }
            }
        }

        // 【统一触发函数】
        function triggerKey() {
            keyBtnRoot.clicked()
            focusRestorer.restart()
        }
    }

    // --- 辅助组件：字符按键 (封装大小写逻辑) ---
    component CharKey : KeyButton {
        Layout.fillWidth: true; Layout.preferredWidth: 1
        Layout.fillHeight: true
        onClicked: insertText(text)
    }

    // --- 逻辑函数 ---
    function getKeyLabel(charKey) {
        if (isSym) return charKey
        return isUpper ? charKey.toUpperCase() : charKey
    }

    function insertText(str) {
        if (!target) return
        var p = target.cursorPosition
        var t = target.text
        target.text = t.slice(0, p) + str + t.slice(p)
        target.cursorPosition = p + str.length
    }

    function moveCursor(offset) {
        if (!target) return
        var newPos = target.cursorPosition + offset
        if (newPos >= 0 && newPos <= target.text.length) {
            target.cursorPosition = newPos
        }
    }

    function handleSpecialKey(key) {
        // 对于普通 TextField，很难模拟特殊键信号
        // 这里留给后续 Terminal 组件扩展接口
        console.log("Special Key:", key)
    }
}
