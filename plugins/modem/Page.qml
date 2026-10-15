pragma ComponentBehavior: Bound

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
    required property string pluginName
    required property url pluginDir

    property var modems: []
    property var connections: []
    property int connectionRefreshGeneration: 0
    property var discoveredApns: []
    property int apnDiscoveryGeneration: 0
    property bool providerDatabaseChecked: false
    property string providerDatabaseXml: ""
    property string providerCacheKey: ""
    property var providerCacheResults: []
    property int selectedModemIndex: 0
    property string selectedModemPath: ""
    property string modemError: ""
    property string networkError: ""
    property bool refreshing: false
    property string editorName: ""
    property string editorApn: ""
    property bool editorAutoconnect: true
    property string editorError: ""
    property var editorConnection: null
    property bool editorExisting: false
    property var deleteConnectionTarget: null

    readonly property var selectedModem: {
        if (root.selectedModemPath) {
            for (var i = 0; i < root.modems.length; ++i) {
                if (root.modems[i].path === root.selectedModemPath) return root.modems[i]
            }
        }
        return root.modems.length > 0 ? root.modems[0] : null
    }

    readonly property var modemChoices: {
        var out = []
        for (var i = 0; i < root.modems.length; ++i) {
            var item = root.modems[i]
            out.push({ "label": root.modemLabel(item), "path": item.path })
        }
        return out
    }

    readonly property int signalQuality: {
        var value = root.valueFromPaths(root.selectedModem, [
            ["data", "modem", "generic", "signal-quality"],
            ["data", "modem", "signal", "quality"],
            ["data", "modem", "signal-quality"]
        ], 0)
        if (value && typeof value === "object") value = value.value
        return Math.max(0, Math.min(100, parseInt(value) || 0))
    }

    readonly property color signalColor: {
        if (root.signalQuality >= 70) return "#4CAF50"
        if (root.signalQuality >= 40) return "#2979FF"
        if (root.signalQuality >= 20) return "#FFC107"
        return "#FF5252"
    }

    readonly property string signalLabel: {
        if (root.signalQuality >= 70) return "Excellent"
        if (root.signalQuality >= 40) return "Good"
        if (root.signalQuality >= 20) return "Weak"
        return root.signalQuality > 0 ? "Very weak" : "No signal"
    }

    readonly property int activeConnectionCount: {
        var count = 0
        for (var i = 0; i < root.connections.length; ++i) {
            if (root.connections[i].active) count++
        }
        return count
    }

    readonly property string errorText: {
        var messages = []
        if (root.modemError) messages.push(root.modemError)
        if (root.networkError) messages.push(root.networkError)
        return messages.join("\n")
    }

    function runTool(program, args, callback) {
        root.api.run("env", ["LC_ALL=C", program].concat(args), callback)
    }

    function readPath(value, path) {
        var current = value
        for (var i = 0; i < path.length; ++i) {
            if (current === null || current === undefined || typeof current !== "object") return undefined
            current = current[path[i]]
        }
        return current
    }

    function valueFromPaths(value, paths, fallback) {
        for (var i = 0; i < paths.length; ++i) {
            var result = readPath(value, paths[i])
            if (result !== undefined && result !== null && String(result) !== "") return result
        }
        return fallback
    }

    function parseJson(text) {
        try { return JSON.parse(text) }
        catch (e) { return null }
    }

    function firstString(value, paths, fallback) {
        var result = valueFromPaths(value, paths, fallback)
        if (result && typeof result === "object") {
            if (result.value !== undefined) result = result.value
            else if (result.name !== undefined) result = result.name
        }
        return result === undefined || result === null || String(result) === "" || String(result) === "--" ? fallback : String(result)
    }

    function modemNode(item) {
        return item && item.data && item.data.modem ? item.data.modem : (item ? item.data : {})
    }

    function modemLabel(item) {
        var node = modemNode(item)
        var model = firstString(node, [["generic", "model"]], "Unknown modem")
        var manufacturer = firstString(node, [["generic", "manufacturer"]], "")
        return manufacturer ? manufacturer + " " + model : model
    }

    function simPath(data) {
        var path = valueFromPaths(data, [
            ["modem", "generic", "sim"],
            ["modem", "sim", "path"],
            ["modem", "generic", "sim", "path"],
            ["modem", "generic", "sim-path"],
            ["modem", "sim-path"]
        ], "")
        return path && typeof path === "string" && path.indexOf("/org/") === 0 ? path : ""
    }

    function modemOperatorCode(item) {
        return firstString(item, [
            ["data", "modem", "3gpp", "operator-code"],
            ["sim", "sim", "properties", "operator-identifier"],
            ["sim", "sim", "operator-identifier"]
        ], "")
    }

    function simImsi(item) {
        return firstString(item, [
            ["sim", "sim", "properties", "imsi"],
            ["sim", "sim", "imsi"]
        ], "")
    }

    function xmlAttribute(tag, name) {
        var expression = new RegExp("\\b" + name + "=\\\"([^\\\"]*)\\\"")
        var match = tag.match(expression)
        return match ? match[1] : ""
    }

    function appendApn(result, seen, apn, carrier, source) {
        var value = String(apn || "").trim()
        if (!value || value === "--") return
        var key = value.toLowerCase()
        if (seen[key]) return
        seen[key] = true
        result.push({
            "apn": value,
            "carrier": String(carrier || "").trim(),
            "source": source,
            "label": String(carrier || "").trim() ? String(carrier).trim() + "  ·  " + value : value
        })
    }

    function appendProviderDatabaseApns(result, seen, item) {
        var code = modemOperatorCode(item)
        var imsi = simImsi(item)
        if (!/^\d{5,6}$/.test(code) && !/^\d{5,15}$/.test(imsi)) return

        var identity = /^\d{5,6}$/.test(code) ? "code:" + code : "imsi:" + imsi
        if (identity === root.providerCacheKey) {
            for (var cachedIndex = 0; cachedIndex < root.providerCacheResults.length; ++cachedIndex) {
                var cached = root.providerCacheResults[cachedIndex]
                appendApn(result, seen, cached.apn, cached.carrier, "Provider database")
            }
            return
        }

        if (!root.providerDatabaseChecked) {
            root.providerDatabaseChecked = true
            root.providerDatabaseXml = root.api.readFile("/usr/share/mobile-broadband-provider-info/apns-conf.xml")
        }
        var xml = root.providerDatabaseXml
        if (!xml) return
        var found = []
        var tagExpression = /<apn\b[^>]*\/>/g
        var tag
        while ((tag = tagExpression.exec(xml)) !== null) {
            var text = tag[0]
            var mcc = xmlAttribute(text, "mcc")
            var mnc = xmlAttribute(text, "mnc")
            var matches = /^\d{5,6}$/.test(code)
                        ? code === mcc + mnc
                        : imsi.indexOf(mcc + mnc) === 0
            if (!matches) continue
            var type = xmlAttribute(text, "type").toLowerCase()
            if (type && type.indexOf("default") < 0 && type.indexOf("supl") < 0) continue
            if (type.indexOf("mms") >= 0) continue
            var apn = xmlAttribute(text, "apn")
            var carrier = xmlAttribute(text, "carrier")
            var description = carrier.toLowerCase()
            var score = 0
            if (type.indexOf("default") >= 0) score += 20
            if (type.indexOf("supl") >= 0) score += 10
            if (description.indexOf("internet") >= 0) score += 40
            if (description.indexOf("data") >= 0 || description.indexOf("broadband") >= 0) score += 25
            if (description.indexOf("wap") >= 0) score -= 30
            if (apn) found.push({ "apn": apn, "carrier": carrier, "score": score })
        }
        found.sort(function(a, b) { return b.score - a.score })
        for (var foundIndex = 0; foundIndex < found.length; ++foundIndex)
            appendApn(result, seen, found[foundIndex].apn, found[foundIndex].carrier, "Provider database")
        root.providerCacheKey = identity
        root.providerCacheResults = found
    }

    function bearerPaths(item) {
        var paths = valueFromPaths(item, [["data", "modem", "generic", "bearers"]], [])
        if (typeof paths === "string") paths = [paths]
        return Array.isArray(paths) ? paths.filter(function(path) { return String(path).indexOf("/org/") === 0 }) : []
    }

    function finishBearerApnDiscovery(paths, index, result, seen, generation) {
        if (generation !== root.apnDiscoveryGeneration) return
        if (index >= paths.length) {
            root.discoveredApns = result
            return
        }
        runTool("mmcli", ["-b", paths[index], "-J"], function(code, out) {
            if (generation !== root.apnDiscoveryGeneration) return
            if (code === 0) {
                var data = parseJson(out) || {}
                appendApn(result, seen, firstString(data, [
                    ["bearer", "properties", "apn"],
                    ["bearer", "3gpp", "apn"]
                ], ""), "Active bearer", "ModemManager")
            }
            finishBearerApnDiscovery(paths, index + 1, result, seen, generation)
        })
    }

    function discoverApns() {
        var generation = ++root.apnDiscoveryGeneration
        var result = []
        var seen = ({})
        for (var i = 0; i < root.connections.length; ++i)
            appendApn(result, seen, root.connections[i].apn, root.connections[i].name, "NetworkManager")

        var item = root.selectedModem
        appendApn(result, seen, firstString(item, [["data", "modem", "3gpp", "eps", "initial-bearer", "settings", "apn"]], ""), "Initial bearer", "ModemManager")
        appendProviderDatabaseApns(result, seen, item)
        root.discoveredApns = result
        finishBearerApnDiscovery(bearerPaths(item), 0, result, seen, generation)
    }

    function finishModemLoad(paths, index, loaded, previousPath) {
        if (index >= paths.length) {
            root.modems = loaded
            root.selectedModemIndex = 0
            root.selectedModemPath = previousPath
            for (var i = 0; i < loaded.length; ++i) {
                if (loaded[i].path === previousPath) root.selectedModemIndex = i
            }
            if (loaded.length > 0 && !root.selectedModemPath) root.selectedModemPath = loaded[0].path
            root.refreshing = false
            root.discoverApns()
            return
        }

        var path = paths[index]
        runTool("mmcli", ["-m", path, "-J"], function(code, out, err) {
            var data = parseJson(out)
            var item = { "path": path, "data": data || {}, "sim": null }
            var sim = simPath(item.data)
            if (!sim) {
                finishModemLoad(paths, index + 1, loaded.concat([item]), previousPath)
                return
            }
            runTool("mmcli", ["-i", sim, "-J"], function(simCode, simOut) {
                item.sim = simCode === 0 ? (parseJson(simOut) || {}) : null
                finishModemLoad(paths, index + 1, loaded.concat([item]), previousPath)
            })
        })
    }

    function refreshModems() {
        var previousPath = root.selectedModemPath || (root.selectedModem ? root.selectedModem.path : "")
        root.refreshing = true
        runTool("mmcli", ["-L", "-J"], function(code, out, err) {
            if (code !== 0) {
                root.modems = []
                root.modemError = "ModemManager unavailable: " + (err || "exit " + code).split("\n")[0]
                root.refreshing = false
                return
            }
            var data = parseJson(out)
            var listed = data && data["modem-list"] ? data["modem-list"] : []
            if (typeof listed === "string") listed = [listed]
            if (!Array.isArray(listed)) listed = []
            root.modemError = ""
            finishModemLoad(listed, 0, [], previousPath)
        })
    }

    function parseMultiline(text) {
        var records = []
        var record = {}
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i].trim()
            if (!line) {
                if (Object.keys(record).length > 0) records.push(record)
                record = {}
                continue
            }
            var separator = line.indexOf(":")
            if (separator < 0) continue
            var key = line.substring(0, separator).trim().toLowerCase()
            if (record[key] !== undefined) {
                records.push(record)
                record = {}
            }
            record[key] = line.substring(separator + 1).trim()
        }
        if (Object.keys(record).length > 0) records.push(record)
        return records
    }

    function recordValue(record, names, fallback) {
        for (var i = 0; i < names.length; ++i) {
            var value = record[names[i].toLowerCase()]
            if (value !== undefined && value !== "") return value
        }
        return fallback
    }

    function unquote(value) {
        var result = String(value || "").trim()
        if (result.length >= 2 && result[0] === '"' && result[result.length - 1] === '"')
            return result.substring(1, result.length - 1).replace(/\\"/g, '"')
        return result
    }

    function finishConnectionDetails(records, index, active, result, generation) {
        if (generation !== root.connectionRefreshGeneration) return
        if (index >= records.length) {
            root.connections = result
            root.networkError = ""
            root.discoverApns()
            return
        }

        var base = records[index]
        var uuid = recordValue(base, ["uuid"], "")
        runTool("nmcli", ["-m", "multiline", "-f", "connection.id,connection.uuid,connection.autoconnect,gsm.apn", "connection", "show", "uuid", uuid], function(code, out) {
            if (generation !== root.connectionRefreshGeneration) return
            var detail = code === 0 ? parseMultiline(out)[0] || {} : {}
            var detailName = unquote(recordValue(detail, ["connection.id", "name"], recordValue(base, ["name"], "Unnamed connection")))
            var detailApn = unquote(recordValue(detail, ["gsm.apn", "apn"], ""))
            var detailAutoconnect = recordValue(detail, ["connection.autoconnect", "autoconnect"], recordValue(base, ["autoconnect"], "yes"))
            result.push({
                "name": detailName,
                "uuid": uuid,
                "apn": detailApn,
                "autoconnect": String(detailAutoconnect).toLowerCase() === "yes",
                "active": active.indexOf(uuid) >= 0
            })
            finishConnectionDetails(records, index + 1, active, result, generation)
        })
    }

    function refreshConnections() {
        var generation = ++root.connectionRefreshGeneration
        runTool("nmcli", ["-m", "multiline", "-f", "NAME,UUID,TYPE,AUTOCONNECT", "connection", "show"], function(code, out, err) {
            if (generation !== root.connectionRefreshGeneration) return
            if (code !== 0) {
                root.connections = []
                root.networkError = "NetworkManager unavailable: " + (err || "exit " + code).split("\n")[0]
                return
            }
            var records = parseMultiline(out)
            runTool("nmcli", ["-t", "--escape", "no", "-f", "UUID", "connection", "show", "--active"], function(activeCode, activeOut) {
                if (generation !== root.connectionRefreshGeneration) return
                var active = activeCode === 0 ? activeOut.split("\n").map(function(s) { return s.trim() }).filter(Boolean) : []
                var gsmRecords = []
                for (var i = 0; i < records.length; ++i) {
                    if (recordValue(records[i], ["type"], "").toLowerCase() === "gsm") gsmRecords.push(records[i])
                }
                finishConnectionDetails(gsmRecords, 0, active, [], generation)
            })
        })
    }

    function refreshAll() {
        root.refreshModems()
        root.refreshConnections()
    }

    function modemState(item) {
        return firstString(item, [["data", "modem", "generic", "state"]], "unknown")
    }

    function modemReady(item) {
        var state = modemState(item)
        var registration = modemRegistration(item)
        return state === "registered" || state === "connected"
            || registration === "home" || registration === "roaming"
    }

    function modemPowerState(item) {
        return firstString(item, [["data", "modem", "generic", "power-state"]], "unknown")
    }

    function modemOperator(item) {
        return firstString(item, [
            ["data", "modem", "3gpp", "operator-name"],
            ["data", "modem", "3gpp", "operator-code"],
            ["data", "modem", "3gpp", "operator-id"]
        ], "Unknown")
    }

    function modemRegistration(item) {
        return firstString(item, [["data", "modem", "3gpp", "registration-state"]], "unknown")
    }

    function modemTechnology(item) {
        return firstString(item, [
            ["data", "modem", "generic", "access-technologies"],
            ["data", "modem", "3gpp", "enabled"]
        ], "Unknown")
    }

    function modemImei(item) {
        return firstString(item, [
            ["data", "modem", "3gpp", "imei"],
            ["data", "modem", "generic", "equipment-identifier"],
            ["data", "modem", "generic", "equipment-id"]
        ], "Unknown")
    }

    function modemRevision(item) {
        return firstString(item, [["data", "modem", "generic", "revision"]], "Unknown")
    }

    function modemDevice(item) {
        return firstString(item, [
            ["data", "modem", "generic", "device"],
            ["data", "modem", "generic", "primary-port"]
        ], "Unknown")
    }

    function simValue(item, paths, fallback) {
        return firstString(item && item.sim ? item.sim : {}, paths, fallback)
    }

    function simLockText(item) {
        if (!item || (!item.sim && !simPath(item.data))) return "Unavailable"
        var required = firstString(item, [
            ["data", "modem", "generic", "unlock-required"],
            ["sim", "sim", "generic", "unlock-required"],
            ["sim", "sim", "unlock-required"]
        ], "")
        if (!required || required === "none" || required === "unknown" || required === "--") return "Unlocked"
        return "Locked (" + required + ")"
    }

    function simRetriesText(item) {
        var retries = valueFromPaths(item, [
            ["data", "modem", "generic", "unlock-retries"],
            ["sim", "sim", "generic", "unlock-retries"],
            ["sim", "sim", "unlock-retries"]
        ], null)
        if (!retries) return ""
        if (Array.isArray(retries)) return retries.join(", ")
        if (typeof retries === "object") {
            var values = []
            for (var key in retries) values.push(key + ": " + retries[key])
            return values.join(", ")
        }
        return String(retries) === "--" ? "" : String(retries)
    }

    function performModemAction(args, successMessage) {
        if (!root.selectedModem) return
        runTool("mmcli", args.concat(["-m", root.selectedModem.path]), function(code, out, err) {
            if (code === 0) {
                root.api.toast(successMessage)
                root.refreshModems()
            } else {
                root.modemError = "Modem action failed: " + (err || out || "exit " + code).split("\n")[0]
            }
        })
    }

    function openCreate() {
        root.editorExisting = false
        root.editorConnection = null
        var suggestion = root.discoveredApns.length > 0 ? root.discoveredApns[0] : null
        var operatorName = root.modemOperator(root.selectedModem)
        root.editorName = suggestion && suggestion.carrier
                        ? suggestion.carrier
                        : (operatorName !== "Unknown" ? operatorName : "Cellular")
        root.editorApn = suggestion ? suggestion.apn : ""
        root.editorAutoconnect = true
        root.editorError = ""
        editorPopup.open()
    }

    function openEdit(connection) {
        root.editorExisting = true
        root.editorConnection = connection
        root.editorName = connection.name
        root.editorApn = connection.apn
        root.editorAutoconnect = connection.autoconnect
        root.editorError = ""
        editorPopup.open()
    }

    function applyApnSuggestion(suggestion) {
        if (!suggestion) return
        root.editorApn = suggestion.apn
        if (!root.editorExisting && suggestion.carrier && (!root.editorName || root.editorName === "Cellular"))
            root.editorName = suggestion.carrier
        apnInput.forceActiveFocus()
        root.showKeyboard(apnInput)
    }

    function showKeyboard(target) {
        if (!target) return
        target.forceActiveFocus()
        modemKeyboard.target = target
        modemKeyboard.visible = true
    }

    function hideKeyboard() {
        modemKeyboard.visible = false
        modemKeyboard.target = null
    }

    function saveConnection() {
        var name = root.editorName.trim()
        var apn = root.editorApn.trim()
        if (!name || !apn) {
            root.editorError = "Connection name and APN are required"
            return
        }
        root.editorError = ""
        var args
        if (root.editorExisting) {
            args = ["connection", "modify", root.editorConnection.uuid,
                    "connection.id", name, "gsm.apn", apn,
                    "connection.autoconnect", root.editorAutoconnect ? "yes" : "no"]
        } else {
            args = ["connection", "add", "type", "gsm", "ifname", "*",
                    "con-name", name, "apn", apn,
                    "autoconnect", root.editorAutoconnect ? "yes" : "no"]
        }
        runTool("nmcli", args, function(code, out, err) {
            if (code === 0) {
                editorPopup.close()
                root.api.toast(root.editorExisting ? "Cellular connection updated" : "Cellular connection created")
                root.refreshConnections()
            } else {
                root.editorError = "Saving connection failed: " + (err || out || "exit " + code).split("\n")[0]
            }
        })
    }

    function deleteConnection(connection) {
        if (!connection) return
        runTool("nmcli", ["connection", "delete", "uuid", connection.uuid], function(code, out, err) {
            if (code === 0) {
                root.api.toast("Cellular connection deleted")
                root.refreshConnections()
            } else {
                root.networkError = "Deleting connection failed: " + (err || out || "exit " + code).split("\n")[0]
            }
        })
    }

    function setConnectionState(connection, up) {
        if (!connection) return
        var args = ["connection", up ? "up" : "down", "uuid", connection.uuid]
        runTool("nmcli", args, function(code, out, err) {
            if (code === 0) {
                root.api.toast(up ? "Cellular connection activated" : "Cellular connection disconnected")
                root.refreshConnections()
            } else {
                root.networkError = (up ? "Activating" : "Disconnecting") + " connection failed: " + (err || out || "exit " + code).split("\n")[0]
            }
        })
    }

    Component.onCompleted: root.refreshAll()

    Timer {
        interval: 5000
        running: root.visible
        repeat: true
        onTriggered: root.refreshAll()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            color: "#1e1e1e"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 14
                spacing: 0

                Rectangle {
                    Layout.preferredWidth: 64
                    Layout.fillHeight: true
                    radius: 8
                    color: backTap.pressed ? "#333" : "transparent"
                    IconImage {
                        anchors.centerIn: parent
                        source: "qrc:/MyDesktop/Backend/assets/back.svg"
                        sourceSize: Qt.size(48, 48)
                        color: "white"
                    }
                    TapHandler {
                        id: backTap
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: root.api.popPage()
                    }
                }

                Text {
                    text: root.pluginName
                    color: "white"
                    font.bold: true
                    font.pixelSize: 25
                    Layout.leftMargin: 5
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 64
                    Layout.fillHeight: true
                    radius: 8
                    color: refreshTap.pressed ? "#333" : "transparent"
                    IconImage {
                        anchors.centerIn: parent
                        source: "qrc:/MyDesktop/Backend/assets/refresh.svg"
                        sourceSize: Qt.size(26, 26)
                        color: refreshTap.enabled ? "white" : "#666"
                    }
                    TapHandler {
                        id: refreshTap
                        enabled: !root.refreshing
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: root.refreshAll()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.errorText !== ""
            color: "#3a1f1f"
            implicitHeight: errorLabel.implicitHeight + 22
            Text {
                id: errorLabel
                anchors.fill: parent
                anchors.margins: 11
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
                spacing: 18

                Item { Layout.preferredHeight: 8 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                    visible: root.modems.length === 0 && root.modemError === ""
                    color: "#1e1e1e"
                    radius: 16
                    implicitHeight: 180

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 14
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 70
                            Layout.preferredHeight: 70
                            radius: 35
                            color: "#23313b"
                            IconImage {
                                anchors.centerIn: parent
                                source: Qt.resolvedUrl("tower.svg")
                                sourceSize: Qt.size(38, 38)
                                color: "#90caf9"
                            }
                        }
                        Text { text: "No modem detected"; color: "white"; font.bold: true; font.pixelSize: 18; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "Check ModemManager and the modem connection."; color: "#888"; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                    visible: root.modems.length > 0
                    color: "#1e1e1e"
                    radius: 16
                    border.color: "#2d2d2d"
                    border.width: 1
                    implicitHeight: heroColumn.implicitHeight + 36

                    ColumnLayout {
                        id: heroColumn
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 16

                        ComboBox {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            visible: root.modems.length > 1
                            model: root.modemChoices
                            textRole: "label"
                            currentIndex: root.selectedModemIndex
                            background: Rectangle {
                                color: "#292929"
                                radius: 10
                                border.color: parent.activeFocus ? "#2979FF" : "#3d3d3d"
                                border.width: 1
                            }
                            onActivated: {
                                root.selectedModemIndex = currentIndex
                                if (currentIndex >= 0 && currentIndex < root.modems.length)
                                    root.selectedModemPath = root.modems[currentIndex].path
                                root.discoverApns()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16

                            Rectangle {
                                Layout.preferredWidth: 68
                                Layout.preferredHeight: 68
                                radius: 34
                                color: "#23313b"
                                IconImage {
                                    anchors.centerIn: parent
                                    source: Qt.resolvedUrl("tower.svg")
                                    sourceSize: Qt.size(38, 38)
                                    color: "#90caf9"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 5
                                Text {
                                    text: root.modemOperator(root.selectedModem)
                                    color: "white"
                                    font.bold: true
                                    font.pixelSize: 22
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: root.modemLabel(root.selectedModem)
                                    color: "#aaa"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                RowLayout {
                                    spacing: 7
                                    Rectangle {
                                        Layout.preferredWidth: 9
                                        Layout.preferredHeight: 9
                                        radius: 5
                                        color: root.modemReady(root.selectedModem) ? "#4CAF50" : "#FFC107"
                                    }
                                    Text {
                                        text: root.modemRegistration(root.selectedModem) + "  ·  " + root.modemState(root.selectedModem)
                                        color: "#bbb"
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#303030" }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            ActionChip {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                text: "Enable modem"
                                active: root.modemPowerState(root.selectedModem) === "on"
                                enabled: root.modemPowerState(root.selectedModem) !== "on"
                                onTapped: root.performModemAction(["--enable"], "Modem enabled")
                            }
                            ActionChip {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                text: "Disable"
                                danger: true
                                enabled: root.modemPowerState(root.selectedModem) === "on"
                                onTapped: root.performModemAction(["--disable"], "Modem disabled")
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                    visible: root.modems.length > 0
                    color: "#18242c"
                    radius: 16
                    border.color: root.signalColor
                    border.width: 1
                    implicitHeight: signalRow.implicitHeight + 36

                    RowLayout {
                        id: signalRow
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 18

                        SignalBars {
                            strength: root.signalQuality
                            activeColor: root.signalColor
                            Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text { text: "Mobile signal"; color: "#90a4ae"; font.pixelSize: 12 }
                            Text { text: root.signalLabel; color: "white"; font.bold: true; font.pixelSize: 20 }
                            Text { text: root.modemTechnology(root.selectedModem); color: root.signalColor; font.pixelSize: 13; font.bold: true }
                        }

                        Text {
                            text: root.signalQuality + "%"
                            color: root.signalColor
                            font.bold: true
                            font.pixelSize: 24
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                    visible: root.modems.length > 0
                    color: "#1e1e1e"
                    radius: 16
                    implicitHeight: modemDetailsColumn.implicitHeight + 36

                    ColumnLayout {
                        id: modemDetailsColumn
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 10
                        Text { text: "Modem details"; color: "white"; font.bold: true; font.pixelSize: 18 }
                        Text { text: "Hardware and network registration information"; color: "#777"; font.pixelSize: 11 }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#303030" }
                        InfoRow { label: "Registration"; valueText: root.modemRegistration(root.selectedModem) }
                        InfoRow { label: "Power state"; valueText: root.modemPowerState(root.selectedModem) }
                        InfoRow { label: "IMEI"; valueText: root.modemImei(root.selectedModem); monospace: true }
                        InfoRow { label: "Device"; valueText: root.modemDevice(root.selectedModem) }
                        InfoRow {
                            label: "Firmware"
                            valueText: root.modemRevision(root.selectedModem)
                            clickable: true
                            onTapped: firmwarePopup.open()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                    visible: root.modems.length > 0
                    color: "#1e1e1e"
                    radius: 16
                    implicitHeight: simDetailsColumn.implicitHeight + 36

                    ColumnLayout {
                        id: simDetailsColumn
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "SIM card"; color: "white"; font.bold: true; font.pixelSize: 18; Layout.fillWidth: true }
                            Text { text: root.simLockText(root.selectedModem); color: root.simLockText(root.selectedModem).indexOf("Locked") === 0 ? "#ffcc80" : "#69f0ae"; font.pixelSize: 12 }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#303030" }
                        InfoRow { label: "Operator"; valueText: root.simValue(root.selectedModem, [["sim", "sim", "properties", "operator-name"], ["sim", "sim", "properties", "operator-identifier"], ["sim", "sim", "operator-name"], ["sim", "sim", "operator-id"]], "Unknown") }
                        InfoRow { label: "ICCID"; valueText: root.simValue(root.selectedModem, [["sim", "sim", "properties", "iccid"], ["sim", "sim", "iccid"], ["sim", "sim", "generic", "iccid"]], "Unknown"); monospace: true }
                        InfoRow { label: "IMSI"; valueText: root.simValue(root.selectedModem, [["sim", "sim", "properties", "imsi"], ["sim", "sim", "imsi"]], "Unknown"); monospace: true }
                        InfoRow { visible: root.simRetriesText(root.selectedModem) !== ""; label: "Retries"; valueText: root.simRetriesText(root.selectedModem); warning: true }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                    color: "#1e1e1e"
                    radius: 16
                    implicitHeight: connectionsColumn.implicitHeight + 36

                    ColumnLayout {
                        id: connectionsColumn
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 14

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                spacing: 3
                                Text { text: "Cellular connections"; color: "white"; font.bold: true; font.pixelSize: 18 }
                                Text {
                                    text: root.connections.length + " saved  ·  " + root.activeConnectionCount + " active"
                                    color: "#777"
                                    font.pixelSize: 11
                                }
                            }
                            Item { Layout.fillWidth: true }
                            ActionChip {
                                text: "+ Add"
                                active: true
                                Layout.preferredWidth: 88
                                Layout.preferredHeight: 40
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                onTapped: root.openCreate()
                            }
                        }

                        Rectangle {
                            visible: root.discoveredApns.length > 0
                            Layout.fillWidth: true
                            color: "#202d36"
                            radius: 10
                            implicitHeight: apnHint.implicitHeight + 20
                            Text {
                                id: apnHint
                                anchors.fill: parent
                                anchors.margins: 10
                                text: root.discoveredApns.length + (root.discoveredApns.length === 1 ? " APN recommendation available" : " APN recommendations available")
                                color: "#90caf9"
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Text {
                            visible: root.connections.length === 0
                            text: "No cellular connections yet. Add one to start mobile data."
                            color: "#888"
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            Layout.bottomMargin: 10
                        }

                        Repeater {
                            model: root.connections
                            delegate: Rectangle {
                                id: connectionDelegate
                                required property var modelData
                                readonly property var connection: modelData
                                Layout.fillWidth: true
                                color: connection.active ? "#203329" : "#292929"
                                radius: 12
                                border.color: connection.active ? "#356c4a" : "#363636"
                                border.width: 1
                                implicitHeight: connectionRow.implicitHeight + 28

                                ColumnLayout {
                                    id: connectionRow
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 10

                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text { text: connectionDelegate.connection.name; color: "white"; font.bold: true; font.pixelSize: 17; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Text { text: "UUID " + connectionDelegate.connection.uuid.substring(0, 8); color: "#777"; font.pixelSize: 10; font.family: "Monospace" }
                                        }
                                        Rectangle {
                                            implicitWidth: stateLabel.implicitWidth + 18
                                            implicitHeight: 28
                                            radius: 14
                                            color: connectionDelegate.connection.active ? "#285c3b" : "#333"
                                            Text {
                                                id: stateLabel
                                                anchors.centerIn: parent
                                                text: connectionDelegate.connection.active ? "Active" : "Inactive"
                                                color: connectionDelegate.connection.active ? "#8cf0b2" : "#aaa"
                                                font.pixelSize: 11
                                                font.bold: connectionDelegate.connection.active
                                            }
                                        }
                                    }

                                    InfoRow { label: "APN"; valueText: connectionDelegate.connection.apn || "Not set"; monospace: true }
                                    InfoRow { label: "Autoconnect"; valueText: connectionDelegate.connection.autoconnect ? "Enabled" : "Disabled" }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        ActionChip { Layout.fillWidth: true; Layout.preferredHeight: 42; text: connectionDelegate.connection.active ? "Disconnect" : "Connect"; active: !connectionDelegate.connection.active; onTapped: root.setConnectionState(connectionDelegate.connection, !connectionDelegate.connection.active) }
                                        ActionChip { Layout.fillWidth: true; Layout.preferredHeight: 42; text: "Edit"; onTapped: root.openEdit(connectionDelegate.connection) }
                                        ActionChip { Layout.fillWidth: true; Layout.preferredHeight: 42; text: "Delete"; danger: true; onTapped: { root.deleteConnectionTarget = connectionDelegate.connection; confirmPopup.open() } }
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 18 }
            }
        }
    }

    Popup {
        id: editorPopup
        parent: Overlay.overlay
        modal: true
        focus: true
        width: Math.min(parent.width - 28, 340)
        height: editorColumn.implicitHeight + 28
        x: Math.round((parent.width - width) / 2)
        y: Math.max(8, Math.round((parent.height - (modemKeyboard.visible ? modemKeyboard.height : 0) - height) / 2))
        z: 9000
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { color: "#1e1e1e"; radius: 14; border.color: "#3d3d3d"; border.width: 1 }
        onOpened: Qt.callLater(function() { root.showKeyboard(nameInput) })
        onClosed: root.hideKeyboard()

        ColumnLayout {
            id: editorColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            Text { text: root.editorExisting ? "Edit cellular connection" : "New cellular connection"; color: "white"; font.bold: true; font.pixelSize: 18 }

            Text { text: "Connection name"; color: "#888"; font.pixelSize: 12 }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                color: "#2a2a2a"
                radius: 8
                border.color: nameInput.activeFocus ? "#0079DB" : "#3d3d3d"
                border.width: 1

                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: "white"
                    font.pixelSize: 16
                    clip: true
                    text: root.editorName
                    onTextChanged: root.editorName = text
                    onActiveFocusChanged: if (activeFocus) root.showKeyboard(nameInput)
                    TapHandler { onTapped: root.showKeyboard(nameInput) }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: "APN"; color: "#888"; font.pixelSize: 12; Layout.fillWidth: true }
                Text {
                    visible: root.discoveredApns.length > 0
                    text: "Auto-detected"
                    color: "#64b5f6"
                    font.pixelSize: 11
                }
            }

            ComboBox {
                id: apnSuggestions
                Layout.fillWidth: true
                visible: root.discoveredApns.length > 0
                model: root.discoveredApns
                textRole: "label"
                displayText: "Choose a detected APN"
                background: Rectangle {
                    color: "#242f38"
                    radius: 8
                    border.color: "#315a77"
                    border.width: 1
                }
                onActivated: root.applyApnSuggestion(root.discoveredApns[currentIndex])
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                color: "#2a2a2a"
                radius: 8
                border.color: apnInput.activeFocus ? "#0079DB" : "#3d3d3d"
                border.width: 1

                TextInput {
                    id: apnInput
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: "white"
                    font.pixelSize: 16
                    font.family: "Monospace"
                    clip: true
                    text: root.editorApn
                    onTextChanged: root.editorApn = text
                    onActiveFocusChanged: if (activeFocus) root.showKeyboard(apnInput)
                    TapHandler { onTapped: root.showKeyboard(apnInput) }
                }
            }

            Text {
                visible: root.discoveredApns.length === 0
                text: "No APN could be detected. Enter the carrier APN manually."
                color: "#777"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Text {
                visible: root.editorError !== ""
                text: root.editorError
                color: "#ff8a80"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: "Autoconnect"; color: "#bbb"; Layout.fillWidth: true }
                Switch { checked: root.editorAutoconnect; onToggled: root.editorAutoconnect = checked }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Item { Layout.fillWidth: true }
                ActionChip { text: "Cancel"; onTapped: editorPopup.close() }
                ActionChip { text: "Save"; active: true; onTapped: root.saveConnection() }
            }
        }
    }

    Popup {
        id: confirmPopup
        parent: Overlay.overlay
        modal: true
        focus: true
        width: Math.min(parent.width - 40, 320)
        height: confirmColumn.implicitHeight + 28
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        z: 9000
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { color: "#1e1e1e"; radius: 14; border.color: "#3d3d3d"; border.width: 1 }

        ColumnLayout {
            id: confirmColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12
            Text { text: "Delete cellular connection?"; color: "white"; font.bold: true; font.pixelSize: 17 }
            Text { text: root.deleteConnectionTarget ? root.deleteConnectionTarget.name : ""; color: "#bbb"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Item { Layout.fillWidth: true }
                ActionChip { text: "Cancel"; onTapped: confirmPopup.close() }
                ActionChip { text: "Delete"; danger: true; onTapped: { var target = root.deleteConnectionTarget; confirmPopup.close(); root.deleteConnection(target) } }
            }
        }
    }

    Popup {
        id: firmwarePopup
        parent: Overlay.overlay
        modal: true
        focus: true
        width: Math.min(parent.width - 36, 420)
        height: firmwareColumn.implicitHeight + 32
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        z: 9000
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: "#1e1e1e"; radius: 14; border.color: "#3d3d3d"; border.width: 1 }

        ColumnLayout {
            id: firmwareColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            Text {
                text: "Firmware revision"
                color: "white"
                font.bold: true
                font.pixelSize: 18
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#303030" }

            Text {
                text: root.modemRevision(root.selectedModem)
                color: "#ddd"
                font.pixelSize: 13
                font.family: "Monospace"
                wrapMode: Text.WrapAnywhere
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                ActionChip { text: "Close"; active: true; onTapped: firmwarePopup.close() }
            }
        }
    }

    CustomKeyboard {
        id: modemKeyboard
        parent: Overlay.overlay
        width: parent ? parent.width : root.width
        z: 10000
        visible: false
        onEnterClicked: {
            if (target === nameInput) root.showKeyboard(apnInput)
            else {
                root.hideKeyboard()
                root.saveConnection()
            }
        }
        onHideClicked: root.hideKeyboard()
    }

    component ActionChip : Rectangle {
        id: chip
        property alias text: chipText.text
        property bool active: false
        property bool danger: false
        signal tapped()

        implicitWidth: 82
        implicitHeight: 36
        radius: height / 2
        opacity: chip.enabled ? 1.0 : 0.45
        color: chip.active
               ? "#0079DB"
               : (chip.danger
                  ? (chipTap.pressed ? "#4a2020" : "#332a2a")
                  : (chipTap.pressed ? "#333" : "#242424"))
        border.color: chip.active ? "#38A7FF" : (chip.danger ? "#FF5252" : "#3d3d3d")
        border.width: 1

        Text {
            id: chipText
            anchors.centerIn: parent
            width: parent.width - 14
            color: chip.danger ? "#FF8A80" : "white"
            font.pixelSize: 12
            font.bold: chip.active
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        TapHandler {
            id: chipTap
            enabled: chip.enabled
            onTapped: chip.tapped()
        }
    }

    component InfoRow : RowLayout {
        id: infoRow
        property string label: ""
        property string valueText: ""
        property bool monospace: false
        property bool warning: false
        property bool clickable: false
        signal tapped()

        Layout.fillWidth: true
        Layout.preferredHeight: 32
        spacing: 12

        Text {
            text: infoRow.label
            color: "#888"
            font.pixelSize: 12
            Layout.preferredWidth: 92
        }

        Text {
            text: infoRow.valueText
            color: infoRow.warning ? "#ffcc80" : "white"
            font.pixelSize: 12
            font.family: infoRow.monospace ? "Monospace" : "Sans Serif"
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideMiddle
            Layout.fillWidth: true
        }

        Text {
            visible: infoRow.clickable
            text: "›"
            color: "#64b5f6"
            font.pixelSize: 20
            Layout.preferredWidth: 12
        }

        TapHandler {
            enabled: infoRow.clickable
            onTapped: infoRow.tapped()
        }
    }

    component SignalBars : Item {
        id: signalBarsRoot
        property int strength: 0
        property color activeColor: "#2979FF"

        implicitWidth: 72
        implicitHeight: 54

        Row {
            anchors.fill: parent
            spacing: 5

            Repeater {
                model: 5
                delegate: Item {
                    id: barSlot
                    required property int index
                    width: 10
                    height: 54

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 12 + barSlot.index * 9
                        radius: 4
                        color: signalBarsRoot.strength >= (barSlot.index === 0 ? 1 : barSlot.index * 20)
                               ? signalBarsRoot.activeColor
                               : "#3b4850"
                    }
                }
            }
        }
    }

    Component.onDestruction: root.hideKeyboard()
}
