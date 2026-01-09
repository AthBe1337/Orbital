import QtQuick

Item {
    id: root
    
    // --- 公共接口 ---
    property var inputData: []         // 数据源 (Array/List)
    property color lineColor: "#00E5FF"
    property bool showGradient: true   // 是否显示线下方的渐变填充
    property double fixedMax: -1       // 如果设为 100，则由 0-100 固定。设为 -1 则自动计算最大值(用于网络)
    property string suffix: ""         // 纵轴单位

    // 内部处理后的最大值
    property double _maxY: 100 

    onInputDataChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        // 开启抗锯齿，线条更平滑
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded

        onPaint: {
            var ctx = getContext("2d");
            var w = width;
            var h = height;
            var data = root.inputData;
            
            // 1. 清空画布
            ctx.clearRect(0, 0, w, h);

            if (!data || data.length < 2) return;

            // 2. 计算量程 (Scale)
            var currentMax = 0;
            if (root.fixedMax > 0) {
                currentMax = root.fixedMax;
            } else {
                // 自动寻找最大值 (用于网络流量)
                for (var k = 0; k < data.length; k++) {
                    if (data[k] > currentMax) currentMax = data[k];
                }
                if (currentMax === 0) currentMax = 10; // 防止除以0
                currentMax = currentMax * 1.2; // 留出 20% 顶部余量
            }
            root._maxY = currentMax; // 暴露出去给 Label 使用

            // 3. 绘制背景网格 (可选，画 3 条水平线)
            ctx.strokeStyle = "#333333";
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(0, h * 0.25); ctx.lineTo(w, h * 0.25);
            ctx.moveTo(0, h * 0.50); ctx.lineTo(w, h * 0.50);
            ctx.moveTo(0, h * 0.75); ctx.lineTo(w, h * 0.75);
            ctx.stroke();

            // 4. 计算坐标点辅助函数
            var stepX = w / (data.length - 1);
            function getY(val) {
                return h - (val / currentMax * h);
            }

            // 5. 绘制折线路径
            ctx.beginPath();
            ctx.moveTo(0, getY(data[0]));
            
            for (var i = 1; i < data.length; i++) {
                // 使用贝塞尔曲线使线条变圆滑 (简单的平滑处理)
                // 如果想要绝对精确的折线，改用 ctx.lineTo(i * stepX, getY(data[i]));
                var x = i * stepX;
                var y = getY(data[i]);
                ctx.lineTo(x, y);
            }

            // 6. 绘制渐变填充 (如果开启)
            if (root.showGradient) {
                // 保存当前路径状态（纯线条）
                ctx.save();
                
                // 闭合路径到底部
                ctx.lineTo(w, h);
                ctx.lineTo(0, h);
                ctx.closePath();

                // 创建线性渐变
                var gradient = ctx.createLinearGradient(0, 0, 0, h);
                // 顶部颜色：线条颜色但半透明
                gradient.addColorStop(0, Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, 0.5));
                // 底部颜色：完全透明
                gradient.addColorStop(1, Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, 0.0));
                
                ctx.fillStyle = gradient;
                ctx.fill();
                ctx.restore(); // 恢复到还没闭合的状态，准备画线
            }

            // 7. 绘制线条描边
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            ctx.strokeStyle = root.lineColor;
            ctx.lineWidth = 2;
            ctx.stroke();
        }
    }

    // 显示最大值标签 (左上角)
    Text {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 4
        text: root.fixedMax > 0 ? root.fixedMax + root.suffix : root._maxY.toFixed(1) + root.suffix
        color: "#666666"
        font.pixelSize: 10
    }
    
    // 显示 0 (左下角)
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 4
        text: "0"
        color: "#666666"
        font.pixelSize: 10
    }
}