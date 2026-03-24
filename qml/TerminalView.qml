import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    required property var terminalBackend

    property string fontFamily: "Noto Sans Mono"
    property int fontPixelSize: terminalBackend ? terminalBackend.fontPixelSize : 15
    property int leftPadding: 10
    property bool selectionMode: false
    property bool followOutput: true

    property int selectionStartRow: -1
    property int selectionStartCol: -1
    property int selectionEndRow: -1
    property int selectionEndCol: -1

    readonly property bool selectionActive: selectionStartRow >= 0 && selectionStartCol >= 0 && selectionEndRow >= 0 && selectionEndCol >= 0
    readonly property int columnCount: terminalBackend ? terminalBackend.columns : 0
    readonly property int computedColumns: Math.max(20, Math.floor((lineList.width - leftPadding - 4) / charWidth))
    readonly property int computedRows: Math.max(8, Math.floor(lineList.height / lineHeight))

    FontMetrics {
        id: terminalMetrics
        font.family: root.fontFamily
        font.pixelSize: root.fontPixelSize
    }

    readonly property real charWidth: Math.max(7, terminalMetrics.averageCharacterWidth)
    readonly property real lineHeight: Math.max(terminalMetrics.height + 4, 20)

    function clearSelection() {
        selectionStartRow = -1
        selectionStartCol = -1
        selectionEndRow = -1
        selectionEndCol = -1
        selectionMode = false
    }

    function scrollToBottom() {
        Qt.callLater(function() {
            if (lineList.count > 0)
                lineList.positionViewAtEnd()
        })
    }

    function normalizedRange() {
        if (!selectionActive)
            return null

        var startRow = selectionStartRow
        var startCol = selectionStartCol
        var endRow = selectionEndRow
        var endCol = selectionEndCol

        if (startRow > endRow || (startRow === endRow && startCol > endCol)) {
            var rowSwap = startRow
            startRow = endRow
            endRow = rowSwap

            var colSwap = startCol
            startCol = endCol
            endCol = colSwap
        }

        return {
            startRow: startRow,
            startCol: startCol,
            endRow: endRow,
            endCol: endCol
        }
    }

    function selectionStartForRow(row) {
        var range = normalizedRange()
        if (!range || row < range.startRow || row > range.endRow)
            return 0
        return row === range.startRow ? range.startCol : 0
    }

    function selectionWidthForRow(row) {
        var range = normalizedRange()
        if (!range || row < range.startRow || row > range.endRow)
            return 0

        var startCol = row === range.startRow ? range.startCol : 0
        var endCol = row === range.endRow ? range.endCol : columnCount
        return Math.max(0, endCol - startCol)
    }

    function beginSelection(x, y) {
        if (lineList.count === 0)
            return

        followOutput = false
        selectionMode = true
        selectionStartRow = rowFromPoint(x, y)
        selectionStartCol = colFromPoint(x, y)
        selectionEndRow = selectionStartRow
        selectionEndCol = selectionStartCol + 1
    }

    function updateSelection(x, y) {
        if (!selectionMode || lineList.count === 0)
            return

        selectionEndRow = rowFromPoint(x, y)
        selectionEndCol = colFromPoint(x, y) + 1
    }

    function contentPoint(x, y) {
        if (!lineList.contentItem)
            return Qt.point(x, y + lineList.contentY)
        return lineList.contentItem.mapFromItem(selectionArea, x, y)
    }

    function rowFromPoint(x, y) {
        if (lineList.count === 0)
            return 0
        var point = contentPoint(x, y)
        var row = Math.floor(point.y / lineHeight)
        return Math.max(0, Math.min(lineList.count - 1, row))
    }

    function colFromPoint(x, y) {
        var point = contentPoint(x, y)
        var available = Math.max(0, point.x - leftPadding)
        var col = Math.floor(available / charWidth)
        return Math.max(0, Math.min(columnCount, col))
    }

    function copySelection() {
        var range = normalizedRange()
        if (!range)
            return

        terminalBackend.copySelection(range.startRow, range.startCol, range.endRow, range.endCol)
    }

    function syncTerminalSize() {
        if (!terminalBackend)
            return
        terminalBackend.resizeTerminal(computedColumns, computedRows)
    }

    Rectangle {
        anchors.fill: parent
        color: "#0f1117"
        border.color: "#242833"
        border.width: 1
        radius: 12
    }

    ListView {
        id: lineList
        anchors.fill: parent
        anchors.margins: 8
        clip: true
        model: terminalBackend ? terminalBackend.lineModel : null
        spacing: 0
        interactive: !root.selectionMode
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true

        delegate: Item {
            required property int index
            width: lineList.width
            height: root.lineHeight
            clip: true

            required property string html

            Rectangle {
                visible: root.selectionWidthForRow(index) > 0
                x: root.leftPadding + root.selectionStartForRow(index) * root.charWidth
                width: Math.max(2, root.selectionWidthForRow(index) * root.charWidth)
                height: parent.height - 2
                y: 1
                radius: 4
                color: "#2A71D0"
                opacity: 0.45
            }

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: root.leftPadding
                anchors.verticalCenter: parent.verticalCenter
                text: html
                textFormat: Text.RichText
                color: "#ECEFF4"
                font.family: root.fontFamily
                font.pixelSize: root.fontPixelSize
                wrapMode: Text.NoWrap
                elide: Text.ElideNone
                clip: true
            }
        }

        onMovementEnded: root.followOutput = lineList.atYEnd
        onFlickStarted: root.followOutput = lineList.atYEnd

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: "#4C566A"
            }
        }
    }

    MouseArea {
        id: selectionArea
        anchors.fill: lineList
        enabled: root.selectionMode
        acceptedButtons: Qt.LeftButton
        onPressed: root.beginSelection(mouse.x, mouse.y)
        onPositionChanged: root.updateSelection(mouse.x, mouse.y)
    }

    Connections {
        target: terminalBackend
        function onScreenChanged() {
            if (root.selectionMode)
                return
            if (root.followOutput || lineList.atYEnd)
                root.scrollToBottom()
        }
    }

    onWidthChanged: syncTerminalSize()
    onHeightChanged: syncTerminalSize()
    onCharWidthChanged: syncTerminalSize()
    onLineHeightChanged: syncTerminalSize()

    Component.onCompleted: {
        syncTerminalSize()
        scrollToBottom()
    }
}
