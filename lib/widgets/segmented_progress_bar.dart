import 'package:flutter/material.dart';

/// 0〜[maxScore] を [segments] 個のブロックで表す（MVP: 各項目は max 10）
class SegmentedProgressBar extends StatelessWidget {
  const SegmentedProgressBar({
    super.key,
    required this.score,
    this.maxScore = 10,
    this.segments = 10,
    this.height = 8,
  });

  final int score;
  final int maxScore;
  final int segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = score.clamp(0, maxScore);
    final filled = (clamped / maxScore * segments).ceil().clamp(0, segments);

    return Row(
      children: List.generate(segments, (i) {
        final active = i < filled;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: height,
              decoration: BoxDecoration(
                color: active ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// 合計行用: 最大 [maxTotal] に対する達成度を無段階（連続）バーで表示
class TotalSegmentedProgressBar extends StatelessWidget {
  const TotalSegmentedProgressBar({
    super.key,
    required this.totalScore,
    this.maxTotal = 100,
    this.height = 8,
  });

  final int totalScore;
  final int maxTotal;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = totalScore.clamp(0, maxTotal);
    final raw = maxTotal == 0 ? 0.0 : clamped / maxTotal;
    // 0点は空、1点以上は最低4%の下駄を履かせて視認できるようにする
    final factor = raw == 0 ? 0.0 : raw.clamp(0.04, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: factor,
        minHeight: height,
        backgroundColor: scheme.surfaceContainerHighest,
        color: scheme.tertiary,
      ),
    );
  }
}
