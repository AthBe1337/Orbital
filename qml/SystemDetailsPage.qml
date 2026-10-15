import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts

Page {
    id: detailsPage
    background: Rectangle { color: "#121212" }

    property var backend
    readonly property var detailsCtrl: backend ? backend.systemDetailsBackend : null
    property int processDisplayCount: 5

    function displayedTopProcesses() {
        if (!detailsCtrl)
            return []

        return detailsCtrl.topProcesses.slice(0, processDisplayCount)
    }

    function syncBackendActiveState() {
        if (detailsCtrl)
            detailsCtrl.active = StackView.status === StackView.Active
    }

    StackView.onStatusChanged: syncBackendActiveState()
    Component.onCompleted: syncBackendActiveState()
    Component.onDestruction: {
        if (detailsCtrl)
            detailsCtrl.active = false
    }

    component SectionCard : Rectangle {
        color: "#1e1e1e"
        radius: 12
        Layout.fillWidth: true
        Layout.leftMargin: 20
        Layout.rightMargin: 20
    }

    component SummaryTile : Rectangle {
        id: tile

        property string label: ""
        property string value: "--"
        property color accentColor: "#81A1C1"
        property bool multiline: false

        Layout.fillWidth: true
        implicitHeight: Math.max(82, tileLayout.implicitHeight + 28)
        radius: 10
        color: "#181D25"
        border.width: 1
        border.color: "#2F3847"

        ColumnLayout {
            id: tileLayout
            anchors.fill: parent
            anchors.margins: 14
            spacing: 5

            Rectangle {
                width: 16
                height: 4
                radius: 2
                color: tile.accentColor
            }

            Text {
                text: tile.label
                color: "#7F8A99"
                font.pixelSize: 11
            }

            Text {
                text: tile.value
                color: "white"
                font.pixelSize: 16
                font.bold: true
                Layout.fillWidth: true
                wrapMode: tile.multiline ? Text.WrapAnywhere : Text.NoWrap
                elide: tile.multiline ? Text.ElideNone : Text.ElideRight
            }
        }
    }

    component EmptyState : Item {
        property string text: ""

        implicitHeight: 88
        Layout.fillWidth: true

        Text {
            anchors.centerIn: parent
            text: parent.text
            color: "#666"
            font.pixelSize: 13
        }
    }

    component CountChip : Rectangle {
        id: chip

        property int value: 0
        property bool active: false

        implicitWidth: 40
        implicitHeight: 30
        radius: 15
        color: active ? "#203546" : (chipTap.pressed ? "#222B36" : "#181D25")
        border.width: 1
        border.color: active ? "#81A1C1" : "#2F3847"

        Text {
            anchors.centerIn: parent
            text: chip.value
            color: active ? "#F4F8FB" : "#AAB6C5"
            font.pixelSize: 12
            font.bold: true
        }

        TapHandler {
            id: chipTap
            onTapped: detailsPage.processDisplayCount = chip.value
        }
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
                        onTapped: stackView.pop()
                    }
                }

                Text {
                    text: "System Details"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 25
                    Layout.leftMargin: 5
                }

                Item { Layout.fillWidth: true }
            }
        }

        ScrollView {
            id: detailsScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: detailsScroll.availableWidth
                spacing: 20

                Item { height: 10 }

                SectionCard {
                    implicitHeight: overviewLayout.implicitHeight + 30

                    ColumnLayout {
                        id: overviewLayout
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 12

                        Text {
                            text: "Overview"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            SummaryTile {
                                label: "Hostname"
                                value: detailsCtrl ? detailsCtrl.hostname : "--"
                                accentColor: "#42A5F5"
                            }

                            SummaryTile {
                                label: "Uptime"
                                value: detailsCtrl ? detailsCtrl.uptime : "--"
                                accentColor: "#FFB020"
                            }
                        }

                        SummaryTile {
                            label: "Primary IP"
                            value: detailsCtrl ? detailsCtrl.primaryIp : "--"
                            multiline: true
                            accentColor: "#00E676"
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            SummaryTile {
                                label: "System"
                                value: backend ? backend.osVersion : "--"
                                multiline: true
                                accentColor: "#8FBCBB"
                            }

                            SummaryTile {
                                label: "Kernel"
                                value: backend ? backend.kernelVersion : "--"
                                multiline: true
                                accentColor: "#A3BE8C"
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            SummaryTile {
                                label: "Load Avg"
                                value: backend ? backend.loadAverage : "--"
                                accentColor: "#88C0D0"
                            }

                            SummaryTile {
                                label: "Root FS"
                                value: backend ? backend.diskRootUsage : "--"
                                accentColor: "#D08770"
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: "#333"
                            visible: detailsCtrl && detailsCtrl.ipAddresses.length > 0
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: detailsCtrl && detailsCtrl.ipAddresses.length > 0

                            Text {
                                text: detailsCtrl ? ("Addresses · " + detailsCtrl.ipAddresses.length) : "Addresses"
                                color: "#888"
                                font.pixelSize: 12
                            }

                            Repeater {
                                model: detailsCtrl ? detailsCtrl.ipAddresses : []

                                delegate: ColumnLayout {
                                    width: parent ? parent.width : 0
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: modelData.interface
                                            color: "#9AA7B7"
                                            font.pixelSize: 12
                                            font.bold: true
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: modelData.family
                                            color: "#666"
                                            font.pixelSize: 11
                                        }
                                    }

                                    Text {
                                        text: modelData.address
                                        color: "white"
                                        font.pixelSize: 13
                                        font.family: "Monospace"
                                        Layout.fillWidth: true
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }
                        }
                    }
                }

                SectionCard {
                    implicitHeight: memLayout.implicitHeight + 30
                    visible: detailsCtrl && detailsCtrl.memoryDetails.length > 0

                    ColumnLayout {
                        id: memLayout
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 12

                        Text {
                            text: "Memory"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Repeater {
                            model: detailsCtrl ? detailsCtrl.memoryDetails : []

                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle {
                                        width: 10
                                        height: 10
                                        radius: 5
                                        color: modelData.color
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Text {
                                        text: modelData.label
                                        color: "#9AA7B7"
                                        font.pixelSize: 13
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: modelData.value
                                        color: "white"
                                        font.pixelSize: 13
                                        font.bold: true
                                        font.family: "Monospace"
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 6
                                    radius: 3
                                    color: "#2A3240"

                                    Rectangle {
                                        width: Math.max(0, Math.min(1, modelData.percent)) * parent.width
                                        height: parent.height
                                        radius: 3
                                        color: modelData.color
                                    }
                                }
                            }
                        }
                    }
                }

                SectionCard {
                    implicitHeight: netSpeedLayout.implicitHeight + 30
                    visible: detailsCtrl && detailsCtrl.networkSpeeds.length > 0

                    ColumnLayout {
                        id: netSpeedLayout
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 12

                        Text {
                            text: "Network Speed"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Repeater {
                            model: detailsCtrl ? detailsCtrl.networkSpeeds : []

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 56
                                radius: 10
                                color: "#181D25"
                                border.width: 1
                                border.color: "#2A3240"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 10

                                    Text {
                                        text: modelData.interface
                                        color: "#9AA7B7"
                                        font.pixelSize: 13
                                        font.bold: true
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    ColumnLayout {
                                        spacing: 2
                                        Layout.alignment: Qt.AlignVCenter

                                        Text {
                                            text: "\u2191 " + modelData.txSpeed
                                            color: "#FF9800"
                                            font.pixelSize: 12
                                            font.family: "Monospace"
                                            horizontalAlignment: Text.AlignRight
                                            Layout.alignment: Qt.AlignRight
                                        }

                                        Text {
                                            text: "\u2193 " + modelData.rxSpeed
                                            color: "#00E676"
                                            font.pixelSize: 12
                                            font.family: "Monospace"
                                            horizontalAlignment: Text.AlignRight
                                            Layout.alignment: Qt.AlignRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                SectionCard {
                    implicitHeight: diskIoLayout.implicitHeight + 30
                    visible: detailsCtrl && detailsCtrl.diskIoSpeeds.length > 0

                    ColumnLayout {
                        id: diskIoLayout
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 12

                        Text {
                            text: "Disk I/O"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Repeater {
                            model: detailsCtrl ? detailsCtrl.diskIoSpeeds : []

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 56
                                radius: 10
                                color: "#181D25"
                                border.width: 1
                                border.color: "#2A3240"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 10

                                    Text {
                                        text: modelData.device
                                        color: "#9AA7B7"
                                        font.pixelSize: 13
                                        font.bold: true
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    ColumnLayout {
                                        spacing: 2
                                        Layout.alignment: Qt.AlignVCenter

                                        Text {
                                            text: "R " + modelData.readSpeed
                                            color: "#42A5F5"
                                            font.pixelSize: 12
                                            font.family: "Monospace"
                                            horizontalAlignment: Text.AlignRight
                                            Layout.alignment: Qt.AlignRight
                                        }

                                        Text {
                                            text: "W " + modelData.writeSpeed
                                            color: "#FF7043"
                                            font.pixelSize: 12
                                            font.family: "Monospace"
                                            horizontalAlignment: Text.AlignRight
                                            Layout.alignment: Qt.AlignRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                SectionCard {
                    implicitHeight: cpuLayout.implicitHeight + 30

                    ColumnLayout {
                        id: cpuLayout
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "CPU Frequencies"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: detailsCtrl ? detailsCtrl.cpuFrequencies.length + " cores" : "--"
                                color: "#777"
                                font.pixelSize: 12
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 10
                            visible: detailsCtrl && detailsCtrl.cpuFrequencies.length > 0

                            Repeater {
                                model: detailsCtrl ? detailsCtrl.cpuFrequencies : []

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 62
                                    radius: 10
                                    color: "#181D25"
                                    border.width: 1
                                    border.color: "#2A3240"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 10

                                        Rectangle {
                                            width: 6
                                            height: parent.height - 8
                                            radius: 3
                                            color: modelData.color
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                text: modelData.label
                                                color: "#93A1B3"
                                                font.pixelSize: 11
                                            }

                                            Text {
                                                text: modelData.displayFreq
                                                color: "white"
                                                font.pixelSize: 17
                                                font.bold: true
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        EmptyState {
                            visible: !detailsCtrl || detailsCtrl.cpuFrequencies.length === 0
                            text: "No CPU frequency data available"
                        }
                    }
                }

                SectionCard {
                    implicitHeight: processLayout.implicitHeight + 30

                    ColumnLayout {
                        id: processLayout
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: "Processes"
                                color: "white"
                                font.pixelSize: 16
                                font.bold: true
                            }

                            Item { Layout.fillWidth: true }

                            Repeater {
                                model: [3, 5, 8, 10]

                                delegate: CountChip {
                                    visible: !detailsCtrl || modelData <= detailsCtrl.topProcessLimit
                                    value: modelData
                                    active: detailsPage.processDisplayCount === modelData
                                }
                            }
                        }

                        Repeater {
                            model: detailsPage.displayedTopProcesses()

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 50
                                radius: 10
                                color: "#181D25"
                                border.width: 1
                                border.color: "#2A3240"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            text: modelData.name
                                            color: "white"
                                            font.pixelSize: 13
                                            font.bold: true
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: "PID " + modelData.pid
                                            color: "#777"
                                            font.pixelSize: 10
                                        }
                                    }

                                    Text {
                                        text: modelData.displayCpu
                                        color: "#FF7043"
                                        font.pixelSize: 13
                                        font.bold: true
                                        horizontalAlignment: Text.AlignRight
                                        Layout.preferredWidth: 44
                                    }

                                    Text {
                                        text: modelData.displayMemory
                                        color: "#8FBCBB"
                                        font.pixelSize: 11
                                        horizontalAlignment: Text.AlignRight
                                        Layout.preferredWidth: 64
                                    }
                                }
                            }
                        }

                        EmptyState {
                            visible: !detailsCtrl || detailsCtrl.topProcesses.length === 0
                            text: "Process usage will appear after the first sample"
                        }
                    }
                }

                SectionCard {
                    implicitHeight: thermalLayout.implicitHeight + 30

                    ColumnLayout {
                        id: thermalLayout
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 12

                        Text {
                            text: "Sensors"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Repeater {
                            model: detailsCtrl ? detailsCtrl.thermalSensors : []

                            delegate: RowLayout {
                                width: parent ? parent.width : 0
                                spacing: 10

                                Rectangle {
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: modelData.color
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Text {
                                    text: modelData.name
                                    color: "white"
                                    font.pixelSize: 13
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: modelData.displayTemp
                                    color: modelData.color
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                            }
                        }

                        EmptyState {
                            visible: !detailsCtrl || detailsCtrl.thermalSensors.length === 0
                            text: "No thermal sensors reported by the kernel"
                        }
                    }
                }

                Item { height: 20 }
            }
        }
    }
}
