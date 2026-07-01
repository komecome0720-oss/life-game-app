import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';

/// 7マスのルーレット盤面。マスの角度（面積）＝当選確率に比例（等分割ではない）。
/// 設定画面のライブプレビューと完了画面のスピン演出で共通利用する。
class RouletteBoard extends StatelessWidget {
  const RouletteBoard({
    super.key,
    required this.cells,
    this.rotation = 0,
    this.size = 240,
  });

  final List<RouletteCell> cells;

  /// 盤面の回転角（ラジアン、時計回り）。スピン演出で使う。プレビューは0。
  final double rotation;
  final double size;

  static Color colorFor(RouletteCategory category, ColorScheme scheme) {
    return switch (category) {
      RouletteCategory.jackpot => const Color(0xFFE53935), // red
      RouletteCategory.chu => const Color(0xFFFFC107), // yellow
      RouletteCategory.sho => const Color(0xFF1E88E5), // blue
      RouletteCategory.miss => const Color(0xFFA7B0BC),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BoardPainter(
          cells: cells,
          rotation: rotation,
          scheme: scheme,
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.cells,
    required this.rotation,
    required this.scheme,
  });

  final List<RouletteCell> cells;
  final double rotation;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 14;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 12時方向を起点に時計回りで描画。盤面全体を rotation で回す。
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);

    const topOffset = -math.pi / 2; // 0(=3時) を 12時へ
    var start = 0.0;
    final divider = Paint()
      ..color = scheme.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final cell in cells) {
      final sweep = cell.sweepFraction * 2 * math.pi;
      final fillColor = RouletteBoard.colorFor(cell.category, scheme);
      final paint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawArc(rect, topOffset + start, sweep, true, paint);
      canvas.drawArc(rect, topOffset + start, sweep, true, divider);

      _drawCellLabel(
        canvas,
        center: center,
        radius: radius,
        angle: topOffset + start + sweep / 2,
        label: _boardLabelFor(cell.category),
        fillColor: fillColor,
        size: size,
      );
      start += sweep;
    }

    // 外周リング
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = scheme.outlineVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    _drawOuterLights(canvas, center: center, radius: radius, size: size);
    canvas.restore();

    // 中央ハブ（回さない）
    canvas.drawCircle(
      center,
      radius * 0.16,
      Paint()..color = scheme.surface,
    );
    canvas.drawCircle(
      center,
      radius * 0.16,
      Paint()
        ..color = scheme.outlineVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 上部の固定ポインタ（下向き三角）
    final pointer = Path()
      ..moveTo(center.dx - 10, center.dy - radius - 4)
      ..lineTo(center.dx + 10, center.dy - radius - 4)
      ..lineTo(center.dx, center.dy - radius + 12)
      ..close();
    canvas.drawPath(pointer, Paint()..color = scheme.onSurface);
  }

  void _drawOuterLights(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Size size,
  }) {
    final lightRadius = math.max(2.0, size.shortestSide * 0.012);
    final orbit = radius + 5;
    final lightPaint = Paint()..style = PaintingStyle.fill;
    const count = 14;
    for (var i = 0; i < count; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / count);
      final isBright = i.isEven;
      final x = center.dx + math.cos(angle) * orbit;
      final y = center.dy + math.sin(angle) * orbit;
      lightPaint.color = isBright
          ? const Color(0xFFFFF1A8)
          : const Color(0xFFFFD36A).withValues(alpha: 0.72);
      canvas.drawCircle(Offset(x, y), lightRadius, lightPaint);
    }
  }

  void _drawCellLabel(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double angle,
    required String label,
    required Color fillColor,
    required Size size,
  }) {
    final textColor = ThemeData.estimateBrightnessForColor(fillColor) ==
            Brightness.light
        ? Colors.black87
        : Colors.white;
    final chars = label.runes.map(String.fromCharCode).toList();
    final baseFontSize = math.max(11.0, size.shortestSide * 0.072);
    final radialStep = baseFontSize * 1.15;
    final maxSpan = radius * 0.48;
    final span = math.max(0, chars.length - 1) * radialStep;
    final scale = span <= maxSpan || span == 0 ? 1.0 : maxSpan / span;
    final fontSize = baseFontSize * scale;
    final glyphStep = fontSize * 1.15;
    final anchorRadius = radius * 0.54;
    final startRadius = anchorRadius - (chars.length - 1) * glyphStep / 2;
    final radialDx = math.cos(angle);
    final radialDy = math.sin(angle);

    for (var i = 0; i < chars.length; i++) {
      final charPainter = TextPainter(
        text: TextSpan(
          text: chars[i],
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
            shadows: const [
              Shadow(
                color: Color(0x80000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      final offsetAlongRadius = startRadius + glyphStep * i;
      final position = Offset(
        center.dx + radialDx * offsetAlongRadius - charPainter.width / 2,
        center.dy + radialDy * offsetAlongRadius - charPainter.height / 2,
      );
      charPainter.paint(canvas, position);
    }
  }

  String _boardLabelFor(RouletteCategory category) {
    return switch (category) {
      RouletteCategory.jackpot => '大',
      RouletteCategory.chu => '中',
      RouletteCategory.sho => '小',
      RouletteCategory.miss => 'ハズレ',
    };
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.rotation != rotation ||
      old.cells != cells ||
      old.scheme != scheme;
}

/// 盤面の凡例（区分→色＋確率%）。設定プレビューで確率を数値でも確認できるようにする。
class RouletteLegend extends StatelessWidget {
  const RouletteLegend({super.key, required this.probabilities});

  final RouletteProbabilities probabilities;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget row(RouletteCategory c, double p) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: RouletteBoard.colorFor(c, scheme),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text('${c.label}  ${(p * 100).toStringAsFixed(1)}%',
                style: text.bodySmall),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 2,
      children: [
        row(RouletteCategory.jackpot, probabilities.jackpot),
        row(RouletteCategory.chu, probabilities.chu),
        row(RouletteCategory.sho, probabilities.sho),
        row(RouletteCategory.miss, probabilities.miss),
      ],
    );
  }
}
