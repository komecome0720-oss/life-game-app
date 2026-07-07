import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:task_manager/features/adventure_log/model/daily_earning.dart';

class CumulativeEarningsChart extends StatelessWidget {
  const CumulativeEarningsChart({
    super.key,
    required this.data,
    required this.height,
  });

  final EarningsWindowData data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');

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
            SizedBox(
              height: height,
              child: CustomPaint(
                painter: _CumulativeChartPainter(
                  points: data.cumulativePoints,
                  period: data.period,
                  colorScheme: Theme.of(context).colorScheme,
                ),
              ),
            ),
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
  });

  final List<CumulativePoint> points;
  final EarningsPeriod period;
  final ColorScheme colorScheme;

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

    const left = 46.0;
    const right = 8.0;
    const top = 8.0;
    const bottom = 28.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      math.max(0, size.width - left - right),
      math.max(0, size.height - top - bottom),
    );

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

    final dateFmt = period == EarningsPeriod.year
        ? DateFormat('yyyy/M')
        : DateFormat('M/d');
    _drawText(
      canvas,
      dateFmt.format(points.first.date),
      Offset(chart.left, chart.bottom + 8),
      labelStyle,
    );
    final endLabel = dateFmt.format(points.last.date);
    _drawText(
      canvas,
      endLabel,
      Offset(chart.right - endLabel.length * 6.0, chart.bottom + 8),
      labelStyle,
    );
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _CumulativeChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.period != period ||
        oldDelegate.colorScheme != colorScheme;
  }
}
