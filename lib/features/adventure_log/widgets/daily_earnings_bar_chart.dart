import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:task_manager/features/adventure_log/model/daily_earning.dart';
import 'package:task_manager/theme/app_tokens.dart';

class DailyEarningsBarChart extends StatelessWidget {
  const DailyEarningsBarChart({
    super.key,
    required this.data,
    required this.height,
  });

  final EarningsWindowData data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // カレンダーの「緊急×非重要」に使う水色・報酬アンバーと揃え、
    // タスク／健康ボーナス／手動調整を一目で見分けられるようにする。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final taskColor = isDark ? Colors.lightBlue.shade300 : Colors.lightBlue.shade700;
    final healthColor = AppColors.positive(context);
    final manualColor = AppColors.reward(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '1日の獲得金額',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: height,
              child: CustomPaint(
                painter: _BarChartPainter(
                  bars: data.bars,
                  period: data.period,
                  colorScheme: colorScheme,
                  taskColor: taskColor,
                  healthColor: healthColor,
                  manualColor: manualColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _LegendChip(color: taskColor, label: 'タスク'),
                _LegendChip(color: healthColor, label: '健康ボーナス'),
                _LegendChip(color: manualColor, label: '手動調整'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _BarChartPainter extends CustomPainter {
  const _BarChartPainter({
    required this.bars,
    required this.period,
    required this.colorScheme,
    required this.taskColor,
    required this.healthColor,
    required this.manualColor,
  });

  final List<DailyBarBucket> bars;
  final EarningsPeriod period;
  final ColorScheme colorScheme;
  final Color taskColor;
  final Color healthColor;
  final Color manualColor;

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 1;

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

    if (bars.isEmpty || chart.width <= 0 || chart.height <= 0) return;

    final maxTotal = bars
        .map((b) => b.total)
        .fold<int>(0, math.max)
        .toDouble();
    final effectiveMax = maxTotal <= 0 ? 1000.0 : maxTotal;

    final slotWidth = chart.width / bars.length;
    final barWidth = math.min(28.0, slotWidth * 0.6);

    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final centerX = chart.left + slotWidth * (i + 0.5);
      var yCursor = chart.bottom;

      void drawSegment(int value, Color color) {
        if (value <= 0) return;
        final segHeight = chart.height * (value / effectiveMax);
        final rect = Rect.fromLTWH(
          centerX - barWidth / 2,
          yCursor - segHeight,
          barWidth,
          segHeight,
        );
        canvas.drawRect(rect, Paint()..color = color);
        yCursor -= segHeight;
      }

      drawSegment(bar.taskYen, taskColor);
      drawSegment(bar.healthYen, healthColor);
      drawSegment(bar.manualYen, manualColor);
    }

    final labelStyle = TextStyle(
      color: colorScheme.onSurfaceVariant,
      fontSize: 10,
    );
    _drawText(
      canvas,
      '¥${NumberFormat.compact().format(effectiveMax.round())}',
      Offset(0, chart.top - 2),
      labelStyle,
    );
    _drawText(canvas, '¥0', Offset(0, chart.bottom - 10), labelStyle);

    final dateFmt = period == EarningsPeriod.year
        ? DateFormat('yyyy/M')
        : DateFormat('M/d');
    _drawText(
      canvas,
      dateFmt.format(bars.first.label),
      Offset(chart.left, chart.bottom + 8),
      labelStyle,
    );
    final endLabel = dateFmt.format(bars.last.label);
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
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.bars != bars ||
        oldDelegate.period != period ||
        oldDelegate.colorScheme != colorScheme;
  }
}
