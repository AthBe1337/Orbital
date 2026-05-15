import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import MyDesktop.Backend 1.0

Rectangle {
    id: root
    color: "#121212"

    required property var api
    required property string pluginId
    required property string mac
    required property string deviceName

    property bool paired: false
    property bool connected: false
    property bool trusted: false
    property bool blocked: false
    property string alias: ""
    property string icon: ""
    property string busyAction: ""
    property string errorText: ""

    // Streaming bluetoothctl session for pair/connect flows.
    property int btProcId: -1
    property string btBuffer: ""
    property string btPhase: ""        // "pairing" | "settle" | "connecting" | "finishing"
    property string passkeyShown: ""   // non-empty while confirm overlay visible
    property string pinPromptType: ""  // "pin" | "passkey" | "" — empty when no input prompt
    property bool confirmHandled: false
    property bool pairResolved: false
    property bool pairSucceeded: false
    property bool connectResolved: false
    property int connectAttempts: 0
    readonly property int maxConnectAttempts: 2

    function readField(text, field) {
        var re = new RegExp("\\b" + field + ":\\s*(.*)")
        var m = text.match(re)
        return m ? m[1].trim() : ""
    }

    function refresh() {
        api.run("bluetoothctl", ["info", root.mac], function(code, out, err) {
            if (code !== 0) {
                root.errorText = "Device info failed: " + (err || out || "exit " + code).split("\n")[0]
                return
            }
            root.errorText = ""
            root.paired = readField(out, "Paired") === "yes"
            root.connected = readField(out, "Connected") === "yes"
            root.trusted = readField(out, "Trusted") === "yes"
            root.blocked = readField(out, "Blocked") === "yes"
            root.alias = readField(out, "Alias")
            root.icon = readField(out, "Icon")
        })
    }

    function performAction(name, args, after) {
        if (root.busyAction !== "") return
        root.busyAction = name
        api.run("bluetoothctl", args, function(code, out, err) {
            root.busyAction = ""
            if (code !== 0) {
                api.toast(name + " failed: " + (err || out || "exit " + code).split("\n")[0])
                root.refresh()
                return
            }
            if (after) after()
            else root.refresh()
        })
    }

    // Drive pair/connect through a long-lived bluetoothctl process so we
    // can react to agent prompts (passkey confirmation, PIN entry) and
    // keep the agent registered until BlueZ has finished bonding. The
    // critical earlier failure was that `bluetoothctl pair MAC` as a
    // one-shot exits the instant the D-Bus Pair() call returns, and BlueZ
    // revokes the bond a moment later because the agent is gone.
    //
    // Output is streamed via api.spawn; we accumulate it in btBuffer and
    // act on patterns:
    //   "Confirm passkey 123456 (yes/no):" → numeric-comparison SSP;
    //       show the passkey, route the user's Yes/No back to stdin.
    //   "Enter PIN code:" / "Enter passkey ..." → legacy PIN entry;
    //       open CustomKeyboard and route typed digits to stdin.
    //   "Pairing successful" / "Failed to pair: …" → transition or abort.
    //   "Connection successful" / "Failed to connect: …" → finish.

    function startSession(name, doPair) {
        if (root.busyAction !== "") return
        root.busyAction = name
        root.btBuffer = ""
        root.passkeyShown = ""
        root.pinPromptType = ""
        root.confirmHandled = false
        root.pairResolved = false
        root.pairSucceeded = false
        root.connectResolved = false
        root.connectAttempts = 0
        root.btPhase = doPair ? "pairing" : "connecting"

        // stdbuf forces line-buffering on bluetoothctl's stdout — when its
        // stdout is a pipe instead of a TTY, glibc would otherwise block-
        // buffer it and we'd miss prompts until many KB had accumulated.
        root.btProcId = api.spawn("stdbuf", ["-oL", "bluetoothctl"],
            function(chunk) {
                root.btBuffer += chunk
                root.handleOutput()
            },
            function(code) {
                root.btProcId = -1
                root.btBuffer = ""
                root.btPhase = ""
                root.passkeyShown = ""
                root.pinPromptType = ""
                root.confirmHandled = false
                root.busyAction = ""
                root.refresh()
            })

        if (root.btProcId === -1) {
            root.busyAction = ""
            api.toast("Failed to launch bluetoothctl")
            return
        }

        // KeyboardDisplay supports the full agent surface: yes/no
        // confirmation (numeric comparison), PIN entry, and passkey entry,
        // plus Just Works fallback for modern devices that need no auth.
        var setup = "agent KeyboardDisplay\ndefault-agent\n"
        if (doPair) {
            setup += "scan on\npair " + root.mac + "\n"
        } else {
            // trust is fast/sync, but kick off connect via the same helper
            // that tracks attempts so retries work uniformly.
            setup += "trust " + root.mac + "\n"
            connectAttemptTimer.restart()
        }
        api.writeStdin(root.btProcId, setup)
    }

    function issueConnect() {
        if (root.btProcId === -1) return
        root.connectAttempts++
        api.writeStdin(root.btProcId, "connect " + root.mac + "\n")
    }

    // Wait after Pairing successful before issuing connect. Two reasons:
    // PipeWire's bluez handler registers A2DP/HFP profiles asynchronously
    // after pair, and BlueZ's auto-pick won't find a "default" profile if
    // we connect mid-registration → br-connection-unknown. Also SDP can
    // still be wrapping up. 1.5s is plenty for both on this device.
    Timer {
        id: settleTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.btProcId === -1) return
            root.btPhase = "connecting"
            api.writeStdin(root.btProcId, "trust " + root.mac + "\n")
            issueConnect()
        }
    }

    Timer {
        id: connectAttemptTimer
        interval: 100
        repeat: false
        onTriggered: issueConnect()
    }

    Timer {
        id: connectRetryTimer
        interval: 2000
        repeat: false
        onTriggered: issueConnect()
    }

    function handleOutput() {
        var b = root.btBuffer

        // SSP numeric comparison — both devices show the same 6-digit code,
        // user confirms. Only react once per prompt.
        if (!root.confirmHandled) {
            var cm = b.match(/Confirm passkey (\d+) \(yes\/no\):/)
            if (cm) {
                root.passkeyShown = cm[1]
                root.confirmHandled = true
            }
        }

        // Legacy PIN code / passkey entry. We don't auto-fill — open the
        // keyboard and let the user type. Same single-fire guard.
        if (!root.pinPromptType) {
            if (/Enter PIN code:/.test(b)) {
                root.pinPromptType = "pin"
            } else if (/Enter passkey \(number/.test(b)) {
                root.pinPromptType = "passkey"
            }
        }

        if (root.btPhase === "pairing" && !root.pairResolved) {
            if (b.indexOf("Pairing successful") !== -1) {
                root.pairResolved = true
                root.pairSucceeded = true
                root.btPhase = "settle"
                settleTimer.restart()
            } else {
                var fp = b.match(/Failed to pair: ([^\n]*)/)
                if (fp) {
                    root.pairResolved = true
                    api.toast("Pair failed: " + fp[1])
                    finishSession()
                }
            }
        }

        if (root.btPhase === "connecting" && !root.connectResolved) {
            if (b.indexOf("Connection successful") !== -1) {
                root.connectResolved = true
                finishSession()
                return
            }

            // Count fails and react only when a new one shows up. Buffer
            // matching alone re-fires on every chunk, so we gate on the
            // count outpacing our attempt counter.
            var allFails = b.match(/Failed to connect: [^\n]*/g)
            if (allFails && allFails.length >= root.connectAttempts) {
                var msg = allFails[allFails.length - 1]
                              .replace(/^Failed to connect: /, "")

                // BlueZ returns AlreadyConnected when the first connect
                // actually went through but our retry raced — treat as
                // success, the device is in the right state.
                if (/AlreadyConnected/i.test(msg)) {
                    root.connectResolved = true
                    finishSession()
                    return
                }

                // `br-connection-unknown` means BlueZ has no registered
                // profile that matches any of the device's UUIDs. That's
                // a system-config state (e.g., PipeWire's spa-bluez5 not
                // loaded for audio devices, or no PAN/HFP handler for
                // phones) — retrying won't fix it. For pair flows the
                // device is now Paired+Bonded which is the user's intent,
                // so finish silently; for explicit Connect requests
                // surface a soft, non-error message instead of "failed".
                if (/br-connection-unknown/i.test(msg)) {
                    root.connectResolved = true
                    if (!root.pairSucceeded) {
                        api.toast("No connectable profile available")
                    }
                    finishSession()
                    return
                }

                if (root.connectAttempts < root.maxConnectAttempts) {
                    // Retry once for the genuinely transient errors
                    // ("Operation in progress", "Not ready", ...).
                    connectRetryTimer.restart()
                } else {
                    root.connectResolved = true
                    api.toast("Connect failed: " + msg)
                    finishSession()
                }
            }
        }
    }

    function finishSession() {
        if (root.btProcId === -1) return
        root.btPhase = "finishing"
        // Best-effort: write quit, then schedule a kill in case the
        // process can't drain a queued async op cleanly.
        api.writeStdin(root.btProcId, "scan off\nquit\n")
        sessionKillTimer.restart()
    }

    function answerConfirm(ok) {
        if (root.btProcId === -1) return
        api.writeStdin(root.btProcId, (ok ? "yes" : "no") + "\n")
        root.passkeyShown = ""
        // Leave confirmHandled true — the same prompt won't fire twice for
        // one pair attempt; if the user said No, the session will quit
        // via Failed-to-pair anyway.
    }

    function answerPinEntry(value) {
        if (root.btProcId === -1) return
        api.writeStdin(root.btProcId, value + "\n")
        root.pinPromptType = ""
    }

    function cancelSession() {
        if (root.btProcId === -1) return
        api.killProc(root.btProcId)
    }

    Timer {
        id: sessionKillTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.btProcId !== -1) api.killProc(root.btProcId)
        }
    }

    function toggleConnect() {
        if (root.connected) {
            performAction("Disconnect", ["disconnect", root.mac])
        } else {
            startSession("Connect", false)
        }
    }
    function togglePair() {
        if (root.paired) {
            performAction("Unpair", ["remove", root.mac], function() { stackView.pop() })
        } else {
            startSession("Pair", true)
        }
    }

    Component.onDestruction: {
        if (root.btProcId !== -1) api.killProc(root.btProcId)
    }
    function toggleTrust() {
        performAction(root.trusted ? "Untrust" : "Trust",
                      [root.trusted ? "untrust" : "trust", root.mac])
    }
    function toggleBlock() {
        performAction(root.blocked ? "Unblock" : "Block",
                      [root.blocked ? "unblock" : "block", root.mac])
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 2500
        running: true
        repeat: true
        onTriggered: if (root.busyAction === "") root.refresh()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            height: 52
            color: "#1e1e1e"

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

                    background: Rectangle {
                        color: parent.pressed ? "#333" : "transparent"
                    }

                    onClicked: stackView.pop()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 5
                    spacing: 0

                    Text {
                        text: root.alias || root.deviceName
                        color: "white"
                        font.bold: true
                        font.pixelSize: 20
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.mac
                        color: "#888"
                        font.pixelSize: 11
                        font.family: "Monospace"
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.errorText !== ""
            color: "#3a1f1f"
            implicitHeight: errLabel.implicitHeight + 18
            Text {
                id: errLabel
                anchors.fill: parent
                anchors.margins: 9
                text: root.errorText
                color: "#ff8a80"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: scroll.availableWidth
                spacing: 20

                Item { height: 6 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    color: "#1e1e1e"
                    radius: 12
                    implicitHeight: statusCol.implicitHeight + 30

                    ColumnLayout {
                        id: statusCol
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 10

                        Text {
                            text: "Status"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        StatusRow { label: "Connected"; on: root.connected }
                        StatusRow { label: "Paired"; on: root.paired }
                        StatusRow { label: "Trusted"; on: root.trusted }
                        StatusRow { label: "Blocked"; on: root.blocked; positiveIsGood: false }
                        StatusRow {
                            label: "Type"
                            valueText: root.icon || "—"
                            visible: root.icon !== ""
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    color: "#1e1e1e"
                    radius: 12
                    implicitHeight: actionsCol.implicitHeight + 30

                    ColumnLayout {
                        id: actionsCol
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 10

                        Text {
                            text: "Actions"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 8

                            ActionChip {
                                text: root.busyAction === "Connect" || root.busyAction === "Disconnect"
                                      ? "…"
                                      : (root.connected ? "Disconnect" : "Connect")
                                active: root.connected
                                enabled: root.busyAction === ""
                                onTapped: root.toggleConnect()
                            }

                            ActionChip {
                                text: root.busyAction === "Pair" || root.busyAction === "Unpair"
                                      ? "…"
                                      : (root.paired ? "Forget" : "Pair")
                                active: root.paired
                                enabled: root.busyAction === ""
                                onTapped: root.togglePair()
                            }

                            ActionChip {
                                text: root.busyAction === "Trust" || root.busyAction === "Untrust"
                                      ? "…"
                                      : (root.trusted ? "Untrust" : "Trust")
                                active: root.trusted
                                enabled: root.busyAction === ""
                                onTapped: root.toggleTrust()
                            }

                            ActionChip {
                                text: root.busyAction === "Block" || root.busyAction === "Unblock"
                                      ? "…"
                                      : (root.blocked ? "Unblock" : "Block")
                                active: root.blocked
                                enabled: root.busyAction === ""
                                onTapped: root.toggleBlock()
                            }
                        }
                    }
                }

                Item { height: 20 }
            }
        }
    }

    // --- Numeric-comparison passkey overlay ---
    // Both devices show this 6-digit number; user confirms or rejects.
    Rectangle {
        id: confirmOverlay
        anchors.fill: parent
        color: "#cc000000"
        visible: root.passkeyShown !== ""
        z: 200

        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 320)
            height: 220
            color: "#1e1e1e"
            radius: 14
            border.color: "#3d3d3d"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 10

                Text {
                    text: "Confirm passkey"
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: root.passkeyShown
                    color: "#0079DB"
                    font.pixelSize: 36
                    font.bold: true
                    font.family: "Monospace"
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Same code on " + (root.alias || root.deviceName) + "?"
                    color: "#888"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ActionChip {
                        text: "No"
                        Layout.fillWidth: true
                        onTapped: root.answerConfirm(false)
                    }
                    ActionChip {
                        text: "Yes"
                        active: true
                        Layout.fillWidth: true
                        onTapped: root.answerConfirm(true)
                    }
                }
            }
        }
    }

    // --- Legacy PIN / passkey entry overlay ---
    Rectangle {
        id: pinOverlay
        anchors.fill: parent
        color: "#cc000000"
        visible: root.pinPromptType !== ""
        z: 200

        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 320)
            height: 180
            color: "#1e1e1e"
            radius: 14
            border.color: "#3d3d3d"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 10

                Text {
                    text: root.pinPromptType === "passkey"
                          ? "Enter passkey"
                          : "Enter PIN"
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    color: "#2a2a2a"
                    radius: 8
                    border.color: pinEntryInput.activeFocus ? "#0079DB" : "#3d3d3d"
                    border.width: 1

                    TextInput {
                        id: pinEntryInput
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        color: "white"
                        font.pixelSize: 18
                        font.family: "Monospace"
                        clip: true
                        focus: root.pinPromptType !== ""
                        validator: RegularExpressionValidator {
                            regularExpression: /^[0-9]{0,6}$/
                        }
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                customKeyboard.target = pinEntryInput
                                customKeyboard.visible = true
                            }
                        }
                        TapHandler {
                            onTapped: {
                                pinEntryInput.forceActiveFocus()
                                customKeyboard.target = pinEntryInput
                                customKeyboard.visible = true
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ActionChip {
                        text: "Cancel"
                        Layout.fillWidth: true
                        onTapped: {
                            pinEntryInput.text = ""
                            customKeyboard.visible = false
                            root.cancelSession()
                        }
                    }
                    ActionChip {
                        text: "OK"
                        active: pinEntryInput.text.length > 0
                        Layout.fillWidth: true
                        onTapped: {
                            if (pinEntryInput.text.length === 0) return
                            var v = pinEntryInput.text
                            pinEntryInput.text = ""
                            customKeyboard.visible = false
                            root.answerPinEntry(v)
                        }
                    }
                }
            }
        }
    }

    CustomKeyboard {
        id: customKeyboard
        width: parent.width
        z: 999
        visible: false
        onEnterClicked: visible = false
        onHideClicked: visible = false
    }

    component StatusRow : RowLayout {
        property string label: ""
        property bool on: false
        property string valueText: ""
        property bool positiveIsGood: true

        Layout.fillWidth: true

        Text {
            text: parent.label
            color: "#aaa"
            font.pixelSize: 12
            Layout.fillWidth: true
        }

        Rectangle {
            visible: parent.valueText === ""
            width: 10; height: 10; radius: 5
            color: parent.on === parent.positiveIsGood ? "#4caf50" : "#555"
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: parent.valueText === ""
            text: parent.on ? "Yes" : "No"
            color: "white"
            font.pixelSize: 12
        }

        Text {
            visible: parent.valueText !== ""
            text: parent.valueText
            color: "white"
            font.pixelSize: 12
        }
    }

    component ActionChip : Rectangle {
        id: chip
        property alias text: chipText.text
        property bool active: false
        property bool enabled: true
        signal tapped()

        implicitWidth: 104
        implicitHeight: 36
        radius: 17
        opacity: chip.enabled ? 1.0 : 0.45
        color: active ? "#0079DB" : (chipTap.pressed ? "#2a2a2a" : "#1e1e1e")
        border.color: active ? "#38A7FF" : "#3d3d3d"
        border.width: 1

        Text {
            id: chipText
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 12
            font.bold: false
            width: parent.width - 20
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        TapHandler {
            id: chipTap
            enabled: chip.enabled
            onTapped: chip.tapped()
        }
    }
}
