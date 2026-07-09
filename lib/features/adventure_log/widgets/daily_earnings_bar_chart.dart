import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:task_manager/features/adventure_log/model/daily_earning.dart';
import 'package:task_manager/theme/app_tokens.dart';

/// [size]と[period]からチャート描画領域を計算する。
/// week表示は各棒の常時ラベル分の余白を確保するため`top`を広げる。
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

/// [dx]の位置から最も近いバーのインデックスを返す。
@visibleForTesting
int nearestBarIndex(double dx, Rect chart, int barCount) {
  if (barCount <= 1) return 0;
  final slotWidth = chart.width / barCount;
  if (slotWidth <= 0) return 0;
  final index = ((dx - chart.left) / slotWidth).floor();
  return index.clamp(0, barCount - 1);
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

class DailyEarningsBarChart extends StatefulWidget {
  const DailyEarningsBarChart({
    super.key,
    required this.data,
    required this.height,
  });

  final EarningsWindowData data;
  final double height;

  @override
  State<DailyEarningsBarChart> createState() => _DailyEarningsBarChartState();
}

class _DailyEarningsBarChartState extends State<DailyEarningsBarChart> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant DailyEarningsBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.period != widget.data.period) {
      setState(() => _selectedIndex = null);
    }
  }

  void _handleDragPosition(Offset localPosition, Size size) {
    final bars = widget.data.bars;
    if (bars.isEmpty) return;
    final chart = chartRectFor(size, widget.data.period);
    final index = nearestBarIndex(localPosition.dx, chart, bars.length);
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
    final colorScheme = Theme.of(context).colorScheme;
    // タスク／健康ボーナス／手動調整を一目で見分けられるように、
    // タスクは水色、健康ボーナスはピンクで固定する。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final taskColor = isDark ? Colors.lightBlue.shade300 : Colors.lightBlue.shade700;
    final healthColor = isDark ? Colors.pink.shade300 : Colors.pink.shade400;
    final manualColor = AppColors.reward(context);

    final data = widget.data;
    final showPermanentLabels = data.period == EarningsPeriod.week;

    Widget chart;
    if (showPermanentLabels) {
      chart = SizedBox(
        height: widget.height,
        child: CustomPaint(
          painter: _BarChartPainter(
            bars: data.bars,
            period: data.period,
            colorScheme: colorScheme,
            taskColor: taskColor,
            healthColor: healthColor,
            manualColor: manualColor,
            selectedIndex: null,
            showPermanentLabels: true,
          ),
        ),
      );
    } else {
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
                painter: _BarChartPainter(
                  bars: data.bars,
                  period: data.period,
                  colorScheme: colorScheme,
                  taskColor: taskColor,
                  healthColor: healthColor,
                  manualColor: manualColor,
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
            Text(
              '1日の獲得金額',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            chart,
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
    required this.selectedIndex,
    required this.showPermanentLabels,
  });

  final List<DailyBarBucket> bars;
  final EarningsPeriod period;
  final ColorScheme colorScheme;
  final Color taskColor;
  final Color healthColor;
  final Color manualColor;
  final int? selectedIndex;
  final bool showPermanentLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 1;

    final chart = chartRectFor(size, period);

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

    double barTotalHeight(DailyBarBucket bar) =>
        chart.height * (bar.total / effectiveMax);

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

    if (!showPermanentLabels && selectedIndex == null) {
      _drawText(
        canvas,
        '¥${NumberFormat.compact().format(effectiveMax.round())}',
        Offset(0, chart.top - 2),
        labelStyle,
      );
      _drawText(canvas, '¥0', Offset(0, chart.bottom - 10), labelStyle);
    }

    final dateFmt = period == EarningsPeriod.year
        ? DateFormat('yyyy/M')
        : DateFormat('M/d');
    for (final index in axisLabelIndices(bars.length)) {
      final centerX = chart.left + slotWidth * (index + 0.5);
      _drawAxisDateLabel(
        canvas,
        dateFmt.format(bars[index].label),
        centerX,
        chart.bottom + 8,
        labelStyle,
        size,
      );
    }

    final amountFmt = NumberFormat('#,###');

    if (showPermanentLabels) {
      for (var i = 0; i < bars.length; i++) {
        final bar = bars[i];
        final centerX = chart.left + slotWidth * (i + 0.5);
        final topY = chart.bottom - barTotalHeight(bar);
        _drawCenteredText(
          canvas,
          '¥${amountFmt.format(bar.total)}',
          Offset(centerX, topY - 14),
          labelStyle,
        );
      }
    }

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < bars.length) {
      final index = selectedIndex!;
      final bar = bars[index];
      final centerX = chart.left + slotWidth * (index + 0.5);
      final totalHeight = barTotalHeight(bar);
      final barRect = Rect.fromLTWH(
        centerX - barWidth / 2,
        chart.bottom - totalHeight,
        barWidth,
        totalHeight,
      );
      canvas.drawRect(
        barRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = colorScheme.primary
          ..strokeWidth = 2,
      );

      final lines = <String>[
        dateFmt.format(bar.label),
        '¥${amountFmt.format(bar.total)}',
      ];
      final lineColors = <Color?>[null, null];
      if (bar.taskYen > 0) {
        lines.add('タスク ¥${amountFmt.format(bar.taskYen)}');
        lineColors.add(taskColor);
      }
      if (bar.healthYen > 0) {
        lines.add('健康ボーナス ¥${amountFmt.format(bar.healthYen)}');
        lineColors.add(healthColor);
      }
      if (bar.manualYen > 0) {
        lines.add('手動調整 ¥${amountFmt.format(bar.manualYen)}');
        lineColors.add(manualColor);
      }

      _drawTooltip(
        canvas,
        chart: chart,
        lines: lines,
        lineColors: lineColors,
        colorScheme: colorScheme,
      );
    }
  }

  void _drawTooltip(
    Canvas canvas, {
    required Rect chart,
    required List<String> lines,
    required List<Color?> lineColors,
    required ColorScheme colorScheme,
  }) {
    const fontSize = 11.0;
    final painters = <TextPainter>[];
    for (var i = 0; i < lines.length; i++) {
      final color = lineColors[i] ?? colorScheme.onInverseSurface;
      final style = TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: i < 2 ? FontWeight.bold : FontWeight.normal,
      );
      painters.add(
        TextPainter(
          text: TextSpan(text: lines[i], style: style),
          textDirection: ui.TextDirection.ltr,
        )..layout(),
      );
    }

    const paddingH = 8.0;
    const paddingV = 6.0;
    const lineGap = 2.0;
    final contentWidth = painters.map((p) => p.width).reduce(math.max);
    final contentHeight =
        painters.map((p) => p.height).reduce((a, b) => a + b) +
        lineGap * (painters.length - 1);
    final boxWidth = contentWidth + paddingH * 2;
    final boxHeight = contentHeight + paddingV * 2;

    final boxRect = Rect.fromLTWH(chart.left, chart.top, boxWidth, boxHeight);
    final rrect = RRect.fromRectAndRadius(boxRect, const Radius.circular(6));
    canvas.drawRRect(rrect, Paint()..color = colorScheme.inverseSurface);

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
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.bars != bars ||
        oldDelegate.period != period ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.showPermanentLabels != showPermanentLabels;
  }
}
