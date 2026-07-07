import 'package:flutter/material.dart';
import 'package:task_manager/models/health_scores.dart';
import 'package:task_manager/widgets/segmented_progress_bar.dart';

class HealthPanel extends StatelessWidget {
  const HealthPanel({super.key, required this.scores, this.onTap});

  final HealthScores scores;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final content = Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('健康管理', style: text.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 6),
          _row(context, '野菜・果物', scores.meal),
          _row(context, '睡眠', scores.sleep),
          _row(context, '運動', scores.exercise),
          _row(context, '瞑想', scores.meditation),
          const Divider(height: 10),
          _totalRow(context, scores.total),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }

  static const _icons = {
    '野菜・果物': Icons.restaurant,
    '睡眠': Icons.bedtime,
    '運動': Icons.directions_run,
    '瞑想': Icons.self_improvement,
  };

  Widget _row(BuildContext context, String label, int score) {
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(_icons[label], size: 16, color: color),
          const SizedBox(width: 4),
          Expanded(child: SegmentedProgressBar(score: score)),
          const SizedBox(width: 4),
          Text('$score', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _totalRow(BuildContext context, int total) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          AnimatedHealthHeart(totalScore: total),
          const SizedBox(width: 4),
          Expanded(child: TotalSegmentedProgressBar(totalScore: total)),
          const SizedBox(width: 4),
          Text('$total/${HealthScores.maxTotal}',
              style: text.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
