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
    property bool isSym2: false
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

    // =========================================================
    // 键盘布局数据定义
    // =========================================================
    
    // --- 字母模式 ---
    readonly property var row1: ["q","w","e","r","t","y","u","i","o","p"]
    readonly property var row2: ["a","s","d","f","g","h","j","k","l"]
    readonly property var row3: ["z","x","c","v","b","n","m"]

    // --- 符号模式 Page 1 (常用数字与标点) ---
    // 行1: 数字
    readonly property var sym1_row1: ["1","2","3","4","5","6","7","8","9","0"]
    // 行2: 常用符号
    readonly property var sym1_row2: ["-","/",":",";","(",")","$","&","@","\""]
    // 行3: 更多标点 (配合 Shift 位置)
    readonly property var sym1_row3: [".",",","?","!","'"]

    // --- 符号模式 Page 2 (更多符号 #+=) ---
    // 行1: 括号与数学
    readonly property var sym2_row1: ["[","]","{","}","#","%","^","*","+","="]
    // 行2: 特殊符号
    readonly property var sym2_row2: ["_","\\","|","~","<",">","€","£","¥","•"]
    // 行3: 其它
    readonly property var sym2_row3: [".",",","?","!","'"] // 保持常用标点方便输入

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
// ============================
        // 1. 第一行 (Row)
        // ============================
        Row {
            Layout.fillWidth: true
            Layout.fillHeight: true // 允许拉伸
            Layout.preferredHeight: 1 // 权重 1
            spacing: 4
            
            // 计算: (总宽 - 总间隙) / 数量
            property real keyWidth: (width - (spacing * (repeater1.count - 1))) / repeater1.count

            Repeater {
                id: repeater1
                model: isSym ? (isSym2 ? sym2_row1 : sym1_row1) : row1
                delegate: KeyButton { 
                    text: getKeyLabel(modelData) 
                    width: parent.keyWidth; height: parent.height
                    onClicked: insertText(text)
                }
            }
        }

        // ============================
        // 2. 第二行 (Row + Padding缩进)
        // ============================
        Row {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1 // 权重 1
            spacing: 4
            
            // 使用 Padding 实现缩进，比 Item 占位更稳
            leftPadding: width * 0.03
            rightPadding: width * 0.03
            property real availableW: width - leftPadding - rightPadding
            property real keyWidth: (availableW - (spacing * (repeater2.count - 1))) / repeater2.count

            Repeater {
                id: repeater2
                model: isSym ? (isSym2 ? sym2_row2 : sym1_row2) : row2
                delegate: KeyButton { 
                    text: getKeyLabel(modelData) 
                    width: parent.keyWidth; height: parent.height
                    onClicked: insertText(text)
                }
            }
        }

        // ============================
        // 3. 第三行 (Row + 混合计算)
        // ============================
        Row {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1 // 权重 1
            spacing: 4

            // 计算逻辑：
            // Shift(1.5) + 中间N个(1.0) + Backspace(1.5)
            // 总权重 = 1.5 + N + 1.5 = N + 3
            // 总间隙 = (N + 2个按键) - 1 = N + 1
            
            property int middleCount: repeater3.count
            property real totalWeight: 1.5 + middleCount + 1.5
            property real totalSpacing: spacing * (middleCount + 1)
            
            // 基础单位宽度 (权重为1的宽度)
            property real unitWidth: (width - totalSpacing) / totalWeight

            // 1. Shift 键 (宽 1.5)
            KeyButton {
                width: parent.unitWidth * 1.5
                height: parent.height
                
                iconSource: !isSym ? (isUpper ? "qrc:/MyDesktop/Backend/assets/shift-filled.svg" : "qrc:/MyDesktop/Backend/assets/shift.svg") : ""
                text: isSym ? (isSym2 ? "123" : "#+=") : "" 
                highlighted: !isSym && isUpper
                
                onClicked: {
                    if (isSym) isSym2 = !isSym2
                    else isUpper = !isUpper
                }
            }

            // 2. 中间字母 (宽 1.0)
            Repeater {
                id: repeater3
                model: isSym ? (isSym2 ? sym2_row3 : sym1_row3) : row3
                delegate: KeyButton { 
                    text: getKeyLabel(modelData) 
                    width: parent.unitWidth // * 1.0
                    height: parent.height
                    onClicked: insertText(text)
                }
            }

            // 3. Backspace 键 (宽 1.5)
            KeyButton {
                width: parent.unitWidth * 1.5
                height: parent.height
                iconSource: "qrc:/MyDesktop/Backend/assets/backspace.svg"
                text: "←"
                repeat: true 
                onClicked: {
                    if (target && target.text.length > 0) {
                        var p = target.cursorPosition
                        if (p > 0) target.remove(p - 1, p)
                    }
                }
            }
        }

        // ============================
        // 4. 第四行 (Row + 混合计算)
        // ============================
        Row {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1 // 权重 1
            spacing: 4

            // 布局：Switch(1.5) - Comma(1) - Space(4) - Dot(1) - Enter(1.5)
            // 总权重 = 1.5 + 1 + 4 + 1 + 1.5 = 9.0
            // 元素数量 = 5，间隙数量 = 4
            
            property real totalWeight: 9.0
            property real unitWidth: (width - (spacing * 4)) / totalWeight

            // 1. Switch
            KeyButton {
                width: parent.unitWidth * 1.5; height: parent.height
                text: isSym ? "ABC" : "?123"
                onClicked: { isSym = !isSym; isSym2 = false }
            }

            // 2. Comma
            KeyButton {
                width: parent.unitWidth * 1.0; height: parent.height
                text: ","
                onClicked: insertText(",")
            }

            // 3. Space
            KeyButton {
                width: parent.unitWidth * 4.0; height: parent.height
                text: "Space"
                onClicked: insertText(" ")
            }

            // 4. Dot
            KeyButton {
                width: parent.unitWidth * 1.0; height: parent.height
                text: "."
                onClicked: insertText(".")
            }

            // 5. Enter
            KeyButton {
                width: parent.unitWidth * 1.5; height: parent.height
                text: terminalMode ? "Enter" : "Done"
                color: "#2979FF"; textColor: "white"
                onClicked: {
                    enterClicked()
                    if (!terminalMode) {
                        keyboard.visible = false
                        if (target) target.focus = false
                    } else {
                        insertText("\n")
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
        
        implicitWidth: 40 
        implicitHeight: 40

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
        Layout.minimumWidth: 0
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
