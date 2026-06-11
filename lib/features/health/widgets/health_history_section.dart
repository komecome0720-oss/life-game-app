import 'package:flutter/material.dart';
import 'package:task_manager/features/health/model/health_category.dart';

class HealthHistorySection extends StatelessWidget {
  const HealthHistorySection({super.key});

  static const double sectionHeight = 236;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final entries = _mockHistoryEntries();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'スコア履歴',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '過去14日',
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: sectionHeight - 40,
              child: ScrollConfiguration(
                behavior: const _NoGlowScrollBehavior(),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    return _HistoryTile(entry: entries[index]);
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final _HealthHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = _scoreColor(scheme, entry.totalScore);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              _formatDate(entry.date),
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: [
                for (final category in HealthCategory.values) ...[
                  _InlineScore(
                    category: category,
                    score: entry.scores[category] ?? 0,
                  ),
                  if (category != HealthCategory.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${entry.totalScore}点',
            style: text.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '¥${_formatYen(entry.earnedYen)}',
            style: text.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.tertiary,
            ),
          ),
        ],
      ),
    );
  }

  Color _scoreColor(ColorScheme scheme, int totalScore) {
    if (totalScore >= 80) return scheme.primary;
    if (totalScore >= 60) return scheme.tertiary;
    return scheme.error;
  }
}

class _InlineScore extends StatelessWidget {
  const _InlineScore({required this.category, required this.score});

  final HealthCategory category;
  final int score;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(category.icon, size: 13, color: scheme.primary),
        const SizedBox(width: 2),
        Text(
          '$score',
          style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _HealthHistoryEntry {
  const _HealthHistoryEntry({
    required this.date,
    required this.scores,
    required this.totalScore,
    required this.earnedYen,
  });

  final DateTime date;
  final Map<HealthCategory, int> scores;
  final int totalScore;
  final int earnedYen;
}

List<_HealthHistoryEntry> _mockHistoryEntries() {
  final today = DateTime.now();
  const seed = <Map<HealthCategory, int>>[
    {
      HealthCategory.meal: 8,
      HealthCategory.exercise: 6,
      HealthCategory.sleep: 9,
      HealthCategory.meditation: 4,
    },
    {
      HealthCategory.meal: 6,
      HealthCategory.exercise: 8,
      HealthCategory.sleep: 7,
      HealthCategory.meditation: 7,
    },
    {
      HealthCategory.meal: 9,
      HealthCategory.exercise: 4,
      HealthCategory.sleep: 8,
      HealthCategory.meditation: 6,
    },
    {
      HealthCategory.meal: 5,
      HealthCategory.exercise: 3,
      HealthCategory.sleep: 6,
      HealthCategory.meditation: 2,
    },
    {
      HealthCategory.meal: 10,
      HealthCategory.exercise: 8,
      HealthCategory.sleep: 10,
      HealthCategory.meditation: 8,
    },
    {
      HealthCategory.meal: 7,
      HealthCategory.exercise: 5,
      HealthCategory.sleep: 8,
      HealthCategory.meditation: 5,
    },
    {
      HealthCategory.meal: 4,
      HealthCategory.exercise: 7,
      HealthCategory.sleep: 5,
      HealthCategory.meditation: 6,
    },
  ];

  return List.generate(14, (index) {
    final scores = seed[index % seed.length];
    final total = HealthCategory.values.fold<int>(
      0,
      (sum, category) => sum + (scores[category] ?? 0) * category.weight,
    );
    return _HealthHistoryEntry(
      date: DateTime(today.year, today.month, today.day - (index + 1)),
      scores: scores,
      totalScore: total,
      earnedYen: total * 92,
    );
  });
}

String _formatDate(DateTime date) => '${date.month}/${date.day}';

String _formatYen(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);

class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
