import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:task_manager/features/adventure_log/model/adventure_log_entry.dart';

class BalanceHistoryChart extends StatelessWidget {
  const BalanceHistoryChart({
    super.key,
    required this.entries,
    required this.currentBalanceYen,
  });

  final List<AdventureLogEntry> entries;
  final int currentBalanceYen;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 29));
    final points = _pointsFor(start, now);
    final fmt = NumberFormat('#,###');
    final latest = points.isEmpty ? currentBalanceYen : points.last.balanceYen;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '所持金の推移',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Text(
                  '¥${fmt.format(latest)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '直近30日',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
              child: CustomPaint(
                painter: _BalanceChartPainter(
                  points: points,
                  rangeStart: start,
                  rangeEnd: now,
                  colorScheme: Theme.of(context).colorScheme,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_BalancePoint> _pointsFor(DateTime start, DateTime end) {
    final ledger = entries
        .where((entry) => entry.affectsChart && entry.occurredAt != null)
        .toList()
      ..sort((a, b) => a.sortAt.compareTo(b.sortAt));

    AdventureLogEntry? beforeStart;
    final within = <AdventureLogEntry>[];
    for (final entry in ledger) {
      if (entry.sortAt.isBefore(start)) {
        beforeStart = entry;
      } else if (!entry.sortAt.isAfter(end)) {
        within.add(entry);
      }
    }

    final startBalance = beforeStart?.balanceAfterYen ??
        (within.isNotEmpty ? within.first.balanceBeforeYen : currentBalanceYen) ??
        currentBalanceYen;

    final points = <_BalancePoint>[_BalancePoint(start, startBalance)];
    for (final entry in within) {
      points.add(_BalancePoint(entry.sortAt, entry.balanceAfterYen!));
    }
    if (points.last.time.isBefore(end)) {
      points.add(_BalancePoint(end, currentBalanceYen));
    }
    return points;
  }
}

class _BalancePoint {
  const _BalancePoint(this.time, this.balanceYen);

  final DateTime time;
  final int balanceYen;
}

class _BalanceChartPainter extends CustomPainter {
  const _BalanceChartPainter({
    required this.points,
    required this.rangeStart,
    required this.rangeEnd,
    required this.colorScheme,
  });

  final List<_BalancePoint> points;
  final DateTime rangeStart;
  final DateTime rangeEnd;
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

    var minY = points.map((p) => p.balanceYen).reduce(math.min);
    var maxY = points.map((p) => p.balanceYen).reduce(math.max);
    if (minY == maxY) {
      minY -= 1000;
      maxY += 1000;
    }
    final spanY = (maxY - minY).toDouble();
    final spanMs = math.max(1, rangeEnd.difference(rangeStart).inMilliseconds);

    Offset mapPoint(_BalancePoint point) {
      final xRatio =
          point.time.difference(rangeStart).inMilliseconds / spanMs;
      final yRatio = (point.balanceYen - minY) / spanY;
      return Offset(
        chart.left + chart.width * xRatio.clamp(0, 1),
        chart.bottom - chart.height * yRatio.clamp(0, 1),
      );
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final mapped = mapPoint(points[i]);
      if (i == 0) {
        path.moveTo(mapped.dx, mapped.dy);
      } else {
        path.lineTo(mapped.dx, mapped.dy);
      }
    }

    final fill = Path.from(path)
      ..lineTo(mapPoint(points.last).dx, chart.bottom)
      ..lineTo(mapPoint(points.first).dx, chart.bottom)
      ..close();
    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(path, linePaint);
    for (final point in points) {
      canvas.drawCircle(mapPoint(point), 3.5, dotPaint);
    }

    final labelStyle = TextStyle(
      color: colorScheme.onSurfaceVariant,
      fontSize: 10,
    );
    _drawText(canvas, '¥${NumberFormat.compact().format(maxY)}',
        Offset(0, chart.top - 2), labelStyle);
    _drawText(canvas, '¥${NumberFormat.compact().format(minY)}',
        Offset(0, chart.bottom - 10), labelStyle);
    final dateFmt = DateFormat('M/d');
    _drawText(canvas, dateFmt.format(rangeStart),
        Offset(chart.left, chart.bottom + 8), labelStyle);
    _drawText(
      canvas,
      dateFmt.format(rangeEnd),
      Offset(chart.right - 28, chart.bottom + 8),
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
  bool shouldRepaint(covariant _BalanceChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.rangeStart != rangeStart ||
        oldDelegate.rangeEnd != rangeEnd;
  }
}
