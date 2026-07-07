import 'package:flutter/material.dart';

/// アプリのブランドマーク（ハート型のゲームコントローラー）。
/// AppIcon・起動画面と同じ形状を、テーマカラーで描画する。
class HeartGamepadIcon extends StatelessWidget {
  const HeartGamepadIcon({super.key, this.size = 64, this.color, this.cutoutColor});

  final double size;
  final Color? color;
  final Color? cutoutColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.square(size),
      painter: _HeartGamepadPainter(
        heartColor: color ?? scheme.primary,
        cutoutColor: cutoutColor ?? scheme.surface,
      ),
    );
  }
}

class _HeartGamepadPainter extends CustomPainter {
  _HeartGamepadPainter({required this.heartColor, required this.cutoutColor});

  final Color heartColor;
  final Color cutoutColor;

  static const _viewBox = 24.0;

  Path _heartPath() {
    final path = Path()
      ..moveTo(12, 21.3)
      ..lineTo(10.56, 19.99)
      ..cubicTo(5.4, 15.36, 2, 12.28, 2, 8.5)
      ..cubicTo(2, 5.42, 4.42, 3, 7.5, 3)
      ..cubicTo(9.24, 3, 10.91, 3.81, 12, 5.09)
      ..cubicTo(13.09, 3.81, 14.76, 3, 16.5, 3)
      ..cubicTo(19.58, 3, 22, 5.42, 22, 8.5)
      ..cubicTo(22, 12.28, 18.6, 15.36, 13.44, 19.99)
      ..lineTo(12, 21.3)
      ..close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _viewBox;
    canvas.save();
    canvas.scale(scale, scale);

    canvas.drawPath(_heartPath(), Paint()..color = heartColor);

    final cutoutPaint = Paint()..color = cutoutColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(5.0, 10.2, 4.6, 1.6), const Radius.circular(0.25)),
      cutoutPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(6.5, 8.7, 1.6, 4.6), const Radius.circular(0.25)),
      cutoutPaint,
    );
    for (final c in const [Offset(16.3, 9.4), Offset(14.7, 11), Offset(17.9, 11), Offset(16.3, 12.6)]) {
      canvas.drawCircle(c, 0.75, cutoutPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeartGamepadPainter oldDelegate) =>
      oldDelegate.heartColor != heartColor || oldDelegate.cutoutColor != cutoutColor;
}
