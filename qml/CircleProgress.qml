import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property double value: 0.0 // 0.0 到 1.0
    property string centerText: "0%"
    property string subText: ""
    property color primaryColor: "#00E5FF"
    property color bgColor: "#333333"
    property int strokeWidth: 8

    Shape {
        id: shape
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4 // 抗锯齿

        // 1. 背景圆环
        ShapePath {
            strokeColor: root.bgColor
            strokeWidth: root.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: (root.width - root.strokeWidth) / 2
                radiusY: (root.height - root.strokeWidth) / 2
                startAngle: 0
                sweepAngle: 360
            }
        }

        // 2. 进度圆环
        ShapePath {
            strokeColor: root.primaryColor
            strokeWidth: root.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: (root.width - root.strokeWidth) / 2
                radiusY: (root.height - root.strokeWidth) / 2
                startAngle: -90 // 从12点钟方向开始
                sweepAngle: 360 * root.value
            }
        }
    }

    // 中心文字
    Column {
        anchors.centerIn: parent
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.centerText
            color: "white"
            font.pixelSize: root.height * 0.2
            font.bold: true
        }
        Text {
            visible: root.subText !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.subText
            color: "#aaaaaa"
            font.pixelSize: root.height * 0.1
        }
    }
}