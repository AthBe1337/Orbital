import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: keyboard
    parent: Overlay.overlay
    z: 99999
    width: parent ? parent.width : 720
    height: terminalMode ? 320 : 270 // 终端模式稍高
    color: "#1C1E26" // 深空灰背景
    radius: 0 // 贴底无需圆角，或仅上方圆角

    // 这是一个滑动弹出的面板，默认在屏幕底部下方
    y: visible ? parent.height - height : parent.height

    // --- 公共接口 ---
    property TextField target: null // 当前控制的输入框
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
                onClicked: {
                    if (target && target.text.length > 0) {
                        var p = target.cursorPosition
                        if (p > 0) {
                            var t = target.text
                            target.text = t.slice(0, p - 1) + t.slice(p)
                            target.cursorPosition = p - 1
                        }
                    }
                }
                // 长按连续删除
                Timer {
                    id: backTimer; interval: 100; repeat: true; running: parent.pressed
                    onTriggered: parent.onClicked()
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
        property string text: ""
        property string iconSource: ""
        property color textColor: "white"
        property bool highlighted: false
        signal clicked()
        property bool pressed: ma.pressed

        color: highlighted ? "#444" : (ma.pressed ? "#333" : "#2D2D2D")
        radius: 6

        // 文本
        Text {
            anchors.centerIn: parent
            text: parent.text
            color: parent.textColor
            font.pixelSize: 18
            visible: parent.iconSource === ""
        }

        // 图标 (如果有)
        IconImage {
            anchors.centerIn: parent
            source: parent.iconSource
            sourceSize: Qt.size(24, 24)
            color: parent.textColor
            visible: parent.iconSource !== ""
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            
            // 【关键修复 1】防止事件冒泡，同时也防止父级 MouseArea (背景那个) 抢夺
            preventStealing: true 
            
            // 【关键修复 2】按下时不获取焦点
            // 注意：TextField 在失去焦点时可能会清除选中状态，所以我们要小心
            onPressed: {
                // 如果 target 存在，强制保持它的焦点状态
                if (target) {
                    target.forceActiveFocus()
                }
            }

            onClicked: {
                // 执行按键逻辑
                parent.clicked()
                
                // 【关键修复 3】再次确保焦点在输入框上
                // 这样光标会一直闪烁，体验才像原生键盘
                if (target) {
                    target.forceActiveFocus()
                }
            }
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
