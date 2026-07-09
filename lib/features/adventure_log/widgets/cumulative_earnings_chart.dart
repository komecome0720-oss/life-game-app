import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:task_manager/features/adventure_log/model/daily_earning.dart';

/// [size]と[period]からチャート描画領域を計算する。
/// week表示は各点の常時ラベル分の余白を確保するため`top`を広げる。
@visibleForTesting
Rect chartRectFor(Size size, EarningsPeriod period) {
  const left = 46.0;
  const right = 8.0;
  final top = period == EarningsPeriod.week ? 22.0 : 8.0;
  const bottom = 28.0;
  return Rect.fromLTWH(
    left,
    top,
    math.max(0, size.width - left - right),
    math.max(0, size.height - top - bottom),
  );
}

/// [dx]の位置から最も近いデータ点のインデックスを返す。
@visibleForTesting
int nearestPointIndex(double dx, Rect chart, int pointCount) {
  if (pointCount <= 1) return 0;
  final ratio = (dx - chart.left) / chart.width;
  return (ratio * (pointCount - 1)).round().clamp(0, pointCount - 1);
}

/// [count]件のデータに対して、日付軸ラベルを描く対象インデックスを返す。
/// 7件以下ならすべて、それ以上なら7件を均等な間隔でサンプリングする。
@visibleForTesting
List<int> axisLabelIndices(int count) {
  if (count <= 0) return const [];
  final labelCount = math.min(7, count);
  if (labelCount == 1) return [0];
  return List.generate(
    labelCount,
    (i) => (i * (count - 1) / (labelCount - 1)).round(),
  );
}

class CumulativeEarningsChart extends StatefulWidget {
  const CumulativeEarningsChart({
    super.key,
    required this.data,
    required this.height,
  });

  final EarningsWindowData data;
  final double height;

  @override
  State<CumulativeEarningsChart> createState() =>
      _CumulativeEarningsChartState();
}

class _CumulativeEarningsChartState extends State<CumulativeEarningsChart> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant CumulativeEarningsChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.period != widget.data.period) {
      setState(() => _selectedIndex = null);
    }
  }

  void _handleDragPosition(Offset localPosition, Size size) {
    final points = widget.data.cumulativePoints;
    if (points.isEmpty) return;
    final chart = chartRectFor(size, widget.data.period);
    final index = nearestPointIndex(localPosition.dx, chart, points.length);
    if (index != _selectedIndex) {
      setState(() => _selectedIndex = index);
    }
  }

  void _clearSelection() {
    if (_selectedIndex != null) {
      setState(() => _selectedIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');
    final data = widget.data;
    final showPermanentLabels = data.period == EarningsPeriod.week;

    Widget chart = SizedBox(
      height: widget.height,
      child: CustomPaint(
        painter: _CumulativeChartPainter(
          points: data.cumulativePoints,
          period: data.period,
          colorScheme: Theme.of(context).colorScheme,
          selectedIndex: showPermanentLabels ? null : _selectedIndex,
          showPermanentLabels: showPermanentLabels,
        ),
      ),
    );

    if (!showPermanentLabels) {
      chart = SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragDown: (details) =>
                  _handleDragPosition(details.localPosition, size),
              onHorizontalDragUpdate: (details) =>
                  _handleDragPosition(details.localPosition, size),
              onHorizontalDragEnd: (_) => _clearSelection(),
              onHorizontalDragCancel: _clearSelection,
              child: CustomPaint(
                painter: _CumulativeChartPainter(
                  points: data.cumulativePoints,
                  period: data.period,
                  colorScheme: Theme.of(context).colorScheme,
                  selectedIndex: _selectedIndex,
                  showPermanentLabels: false,
                ),
              ),
            );
          },
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '合計獲得金額の推移',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '¥${fmt.format(data.totalYen)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            chart,
          ],
        ),
      ),
    );
  }
}

class _CumulativeChartPainter extends CustomPainter {
  const _CumulativeChartPainter({
    required this.points,
    required this.period,
    required this.colorScheme,
    required this.selectedIndex,
    required this.showPermanentLabels,
  });

  final List<CumulativePoint> points;
  final EarningsPeriod period;
  final ColorScheme colorScheme;
  final int? selectedIndex;
  final bool showPermanentLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final dotPaint = Paint()
      ..color = colorScheme.primary
      ..style = PaintingStyle.fill;

    final chart = chartRectFor(size, period);

    canvas.drawLine(chart.bottomLeft, chart.bottomRight, axisPaint);
    canvas.drawLine(chart.topLeft, chart.bottomLeft, axisPaint);

    if (points.isEmpty || chart.width <= 0 || chart.height <= 0) return;

    var minY = points.map((p) => p.cumulativeYen).reduce(math.min);
    var maxY = points.map((p) => p.cumulativeYen).reduce(math.max);
    if (minY == maxY) {
      minY -= 1000;
      maxY += 1000;
    }
    final spanY = (maxY - minY).toDouble();
    final lastIndex = math.max(1, points.length - 1);

    Offset mapPoint(int index) {
      final xRatio = index / lastIndex;
      final yRatio = (points[index].cumulativeYen - minY) / spanY;
      return Offset(
        chart.left + chart.width * xRatio.clamp(0, 1),
        chart.bottom - chart.height * yRatio.clamp(0, 1),
      );
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final mapped = mapPoint(i);
      if (i == 0) {
        path.moveTo(mapped.dx, mapped.dy);
      } else {
        path.lineTo(mapped.dx, mapped.dy);
      }
    }

    final fill = Path.from(path)
      ..lineTo(mapPoint(points.length - 1).dx, chart.bottom)
      ..lineTo(mapPoint(0).dx, chart.bottom)
      ..close();
    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(path, linePaint);

    // 年表示はデータ点が多すぎるためマーカーを描かない。
    if (period != EarningsPeriod.year) {
      for (var i = 0; i < points.length; i++) {
        canvas.drawCircle(mapPoint(i), 3.5, dotPaint);
      }
    }

    final labelStyle = TextStyle(
      color: colorScheme.onSurfaceVariant,
      fontSize: 10,
    );

    if (!showPermanentLabels && selectedIndex == null) {
      _drawText(
        canvas,
        '¥${NumberFormat.compact().format(maxY)}',
        Offset(0, chart.top - 2),
        labelStyle,
      );
      _drawText(
        canvas,
        '¥${NumberFormat.compact().format(minY)}',
        Offset(0, chart.bottom - 10),
        labelStyle,
      );
    }

    final dateFmt = period == EarningsPeriod.year
        ? DateFormat('yyyy/M')
        : DateFormat('M/d');
    for (final index in axisLabelIndices(points.length)) {
      _drawAxisDateLabel(
        canvas,
        dateFmt.format(points[index].date),
        mapPoint(index).dx,
        chart.bottom + 8,
        labelStyle,
        size,
      );
    }

    if (showPermanentLabels) {
      final amountFmt = NumberFormat('#,###');
      for (var i = 0; i < points.length; i++) {
        final mapped = mapPoint(i);
        _drawCenteredText(
          canvas,
          '¥${amountFmt.format(points[i].cumulativeYen)}',
          Offset(mapped.dx, mapped.dy - 14),
          labelStyle,
        );
      }
    }

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < points.length) {
      final index = selectedIndex!;
      final mapped = mapPoint(index);
      final guidePaint = Paint()
        ..color = colorScheme.primary.withValues(alpha: 0.4)
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(mapped.dx, chart.top),
        Offset(mapped.dx, chart.bottom),
        guidePaint,
      );
      canvas.drawCircle(mapped, 5, Paint()..color = colorScheme.primary);

      final amountFmt = NumberFormat('#,###');
      final dateLine = dateFmt.format(points[index].date);
      final amountLine = '¥${amountFmt.format(points[index].cumulativeYen)}';
      _drawTooltip(
        canvas,
        chart: chart,
        lines: [dateLine, amountLine],
        colorScheme: colorScheme,
      );
    }
  }

  void _drawTooltip(
    Canvas canvas, {
    required Rect chart,
    required List<String> lines,
    required ColorScheme colorScheme,
  }) {
    const fontSize = 11.0;
    final textStyle = TextStyle(
      color: colorScheme.onInverseSurface,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
    );
    final painters = lines
        .map(
          (line) => TextPainter(
            text: TextSpan(text: line, style: textStyle),
            textDirection: ui.TextDirection.ltr,
          )..layout(),
        )
        .toList();

    const paddingH = 8.0;
    const paddingV = 6.0;
    const lineGap = 2.0;
    final contentWidth = painters
        .map((p) => p.width)
        .reduce(math.max);
    final contentHeight =
        painters.map((p) => p.height).reduce((a, b) => a + b) +
        lineGap * (painters.length - 1);
    final boxWidth = contentWidth + paddingH * 2;
    final boxHeight = contentHeight + paddingV * 2;

    final boxRect = Rect.fromLTWH(chart.left, chart.top, boxWidth, boxHeight);
    final rrect = RRect.fromRectAndRadius(boxRect, const Radius.circular(6));
    canvas.drawRRect(
      rrect,
      Paint()..color = colorScheme.inverseSurface,
    );

    var dy = boxRect.top + paddingV;
    for (final painter in painters) {
      painter.paint(canvas, Offset(boxRect.left + paddingH, dy));
      dy += painter.height + lineGap;
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy));
  }

  void _drawAxisDateLabel(
    Canvas canvas,
    String text,
    double centerX,
    double y,
    TextStyle style,
    Size canvasSize,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final dx = (centerX - painter.width / 2)
        .clamp(0.0, math.max(0.0, canvasSize.width - painter.width))
        .toDouble();
    painter.paint(canvas, Offset(dx, y));
  }

  @override
  bool shouldRepaint(covariant _CumulativeChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.period != period ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.showPermanentLabels != showPermanentLabels;
  }
}
