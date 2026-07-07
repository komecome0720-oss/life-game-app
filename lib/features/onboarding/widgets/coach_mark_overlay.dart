import 'package:flutter/material.dart';

/// コーチマーク1ステップ分の定義。
class CoachMarkStep {
  const CoachMarkStep({
    required this.targetKey,
    required this.title,
    required this.body,
  });

  /// くり抜き対象のウィジェットに付与された GlobalKey。
  /// null、またはレイアウト未完了・不可視で RenderBox が取得できない場合は
  /// くり抜きなしで中央に吹き出しを表示する（クラッシュさせない）。
  final GlobalKey? targetKey;
  final String title;
  final String body;
}

/// ホーム画面の上に重ねる半透明の黒幕＋吹き出しのコーチマーク（純粋ウィジェット）。
///
/// タップで次のステップへ進む。最終ステップのタップで [onFinished]。
/// 右上の「スキップ」で [onSkipAll]。
class CoachMarkOverlay extends StatefulWidget {
  const CoachMarkOverlay({
    super.key,
    required this.steps,
    required this.onFinished,
    required this.onSkipAll,
  });

  final List<CoachMarkStep> steps;
  final VoidCallback onFinished;
  final VoidCallback onSkipAll;

  @override
  State<CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<CoachMarkOverlay> {
  int _index = 0;

  void _advance() {
    if (_index >= widget.steps.length - 1) {
      widget.onFinished();
      return;
    }
    setState(() => _index++);
  }

  Rect? _targetRect(GlobalKey? key) {
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached || !renderObject.hasSize) {
      return null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    final targetRect = _targetRect(step.targetKey);
    final screenSize = MediaQuery.sizeOf(context);

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _advance,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _CutoutPainter(targetRect: targetRect),
              ),
            ),
            _CoachMarkBubble(
              targetRect: targetRect,
              screenSize: screenSize,
              title: step.title,
              body: step.body,
              stepNumber: _index + 1,
              totalSteps: widget.steps.length,
            ),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: TextButton(
                    onPressed: widget.onSkipAll,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('スキップ'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CutoutPainter extends CustomPainter {
  _CutoutPainter({required this.targetRect});

  final Rect? targetRect;

  static const _padding = 8.0;
  static const _radius = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final rect = targetRect;
    final paint = Paint()..color = Colors.black54;

    if (rect == null) {
      canvas.drawPath(backgroundPath, paint);
      return;
    }

    final inflated = rect.inflate(_padding);
    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(inflated, const Radius.circular(_radius)));

    final combined = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );
    canvas.drawPath(combined, paint);
  }

  @override
  bool shouldRepaint(covariant _CutoutPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect;
  }
}

class _CoachMarkBubble extends StatelessWidget {
  const _CoachMarkBubble({
    required this.targetRect,
    required this.screenSize,
    required this.title,
    required this.body,
    required this.stepNumber,
    required this.totalSteps,
  });

  final Rect? targetRect;
  final Size screenSize;
  final String title;
  final String body;
  final int stepNumber;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    const bubbleMargin = 16.0;
    const bubbleGap = 16.0;

    final content = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text(
              'タップで次へ ($stepNumber/$totalSteps)',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
        ),
      ),
    );

    // targetRect が取れない場合は中央に表示（くり抜き無し）。
    if (targetRect == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: content,
        ),
      );
    }

    final rect = targetRect!;
    final spaceAbove = rect.top;
    final spaceBelow = screenSize.height - rect.bottom;
    final placeBelow = spaceBelow >= spaceAbove;

    return Positioned(
      left: bubbleMargin,
      right: bubbleMargin,
      top: placeBelow ? rect.bottom + bubbleGap : null,
      bottom: placeBelow ? null : screenSize.height - rect.top + bubbleGap,
      child: content,
    );
  }
}
