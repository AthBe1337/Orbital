import QtQuick

// Eagerly-loaded service. Registers a QObject of itself in the cross-plugin
// exports registry so other plugins (e.g. music-player) can drive audio
// output without re-implementing the runuser/pactl gymnastics.
//
// Consumers access this via `api.pluginExports("sound")` and get back this
// QObject; they can read properties, call functions, and connect to signals.
QtObject {
    id: service

    required property var api
    required property string pluginId
    required property string pluginName
    required property url pluginDir

    // ===== Public state =====
    property bool ready: false
    property var sinks: []                  // raw pactl JSON array
    property string defaultSinkName: ""
    property int volumePercent: 0           // 0..100 of default sink
    property bool muted: false

    readonly property var currentSink: {
        for (var i = 0; i < sinks.length; ++i) {
            if (sinks[i].name === defaultSinkName) return sinks[i]
        }
        return sinks.length > 0 ? sinks[0] : null
    }
    readonly property string currentSinkDisplay: service.sinkDisplay(currentSink)

    // ===== Signals (consumers connect via .connect(fn)) =====
    signal volumeChanged(int percent)
    signal defaultSinkChanged(string name)
    signal sinksRefreshed()

    // ===== PipeWire user detection =====
    property string audioUid: ""
    property string audioUser: ""

    function detectRuntime(cb) {
        var probe =
            'for d in /run/user/*; do\n' +
            '  uid=$(basename "$d")\n' +
            '  [ "$uid" = "0" ] && continue\n' +
            '  if [ -S "$d/pulse/native" ] || [ -S "$d/pipewire-0" ]; then\n' +
            '    user=$(id -nu "$uid" 2>/dev/null)\n' +
            '    [ -n "$user" ] && echo "$uid:$user" && exit 0\n' +
            '  fi\n' +
            'done\n' +
            'if [ -S /run/user/0/pulse/native ] || [ -S /run/user/0/pipewire-0 ]; then echo "0:root"; exit 0; fi\n' +
            'exit 1'
        service.api.run("sh", ["-c", probe], function(code, out) {
            if (code === 0) {
                var parts = out.trim().split(":")
                service.audioUid = parts[0]
                service.audioUser = parts[1]
            }
            if (cb) cb()
        })
    }

    function audioRun(prog, args, cb) {
        if (service.audioUser && service.audioUid) {
            var wrapped = ["-u", service.audioUser, "--",
                           "env", "XDG_RUNTIME_DIR=/run/user/" + service.audioUid,
                           prog].concat(args)
            service.api.run("runuser", wrapped, cb)
        } else {
            service.api.run(prog, args, cb)
        }
    }

    // ===== Helpers =====
    function sinkDisplay(sink) {
        if (!sink) return ""
        var p = sink.properties || {}
        return sink.description
            || p["device.description"]
            || p["node.nick"]
            || p["alsa.card_name"]
            || sink.name
    }

    function averagePercent(sink) {
        if (!sink || !sink.volume) return 0
        var sum = 0, n = 0
        for (var ch in sink.volume) {
            var v = sink.volume[ch]
            if (v && v.value_percent) {
                sum += parseInt(String(v.value_percent).replace("%", "").trim()) || 0
                n += 1
            }
        }
        return n > 0 ? Math.round(sum / n) : 0
    }

    // ===== Public API =====
    function refresh(cb) {
        audioRun("pactl", ["-f", "json", "list", "sinks"], function(code, out) {
            if (code === 0) {
                try { service.sinks = JSON.parse(out) || [] }
                catch (e) { service.sinks = [] }
            }
            audioRun("pactl", ["get-default-sink"], function(code2, out2) {
                if (code2 === 0) service.defaultSinkName = out2.trim()
                var snk = service.currentSink
                service.volumePercent = service.averagePercent(snk)
                service.muted = !!(snk && snk.mute)
                service.sinksRefreshed()
                if (cb) cb()
            })
        })
    }

    function listSinks(cb) {
        refresh(function() {
            var out = []
            for (var i = 0; i < service.sinks.length; ++i) {
                var s = service.sinks[i]
                out.push({
                    name: s.name,
                    display: service.sinkDisplay(s),
                    isDefault: s.name === service.defaultSinkName,
                    volumePercent: service.averagePercent(s),
                    muted: !!s.mute
                })
            }
            if (cb) cb(out)
        })
    }

    function setVolume(percent) {
        var p = Math.max(0, Math.min(100, Math.round(percent)))
        var snk = service.currentSink
        if (!snk) return
        audioRun("pactl", ["set-sink-volume", snk.name, p + "%"], function() {
            service.volumePercent = p
            service.volumeChanged(p)
        })
    }

    function setMute(value) {
        var snk = service.currentSink
        if (!snk) return
        audioRun("pactl", ["set-sink-mute", snk.name, value ? "1" : "0"], function() {
            service.muted = !!value
        })
    }

    function setDefaultSink(name) {
        audioRun("pactl", ["set-default-sink", name], function() {
            service.defaultSinkName = name
            service.defaultSinkChanged(name)
            service.refresh()
        })
    }

    Component.onCompleted: {
        // Register synchronously so other plugins can see us right after
        // Main.qml's loader fires. Initial state populates asynchronously.
        service.api.registerExports(service)
        detectRuntime(function() {
            service.refresh(function() { service.ready = true })
        })
    }
}
