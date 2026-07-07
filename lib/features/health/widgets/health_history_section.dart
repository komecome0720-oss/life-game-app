import 'package:flutter/material.dart';
import 'package:task_manager/features/health/model/health_category.dart';
import 'package:task_manager/features/health/model/health_log.dart';
import 'package:task_manager/widgets/empty_state_view.dart';

class HealthHistorySection extends StatelessWidget {
  const HealthHistorySection({
    super.key,
    required this.logs,
    this.isLoading = false,
    this.errorMessage,
  });

  static const double sectionHeight = 236;

  final List<HealthLog> logs;
  final bool isLoading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

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
                  '直近14件',
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(height: sectionHeight - 40, child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final message = errorMessage;
    if (message != null && message.isNotEmpty) {
      return _StatusMessage(
        icon: Icons.error_outline,
        title: '履歴を読み込めませんでした',
        message: message,
      );
    }

    if (logs.isEmpty) {
      return const Center(
        child: EmptyStateView(
          icon: Icons.inbox_outlined,
          message: '保存済みの履歴がありません',
          hint: '過去に保存したスコアがここに表示されます。',
        ),
      );
    }

    return ScrollConfiguration(
      behavior: const _NoGlowScrollBehavior(),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: logs.length,
        itemBuilder: (context, index) {
          return _HistoryTile(entry: logs[index]);
        },
        separatorBuilder: (_, _) => const SizedBox(height: 6),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final HealthLog entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = _scoreColor(scheme, entry.totalScore);
    final earnedYen = entry.isFinalized
        ? entry.finalizedEarnedYen
        : entry.provisionalEarnedYen;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              _formatDateKey(entry.dateKey),
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (final category in HealthCategory.values)
                  _InlineScore(
                    category: category,
                    score: category.score(entry),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 34,
            child: FittedBox(
              alignment: Alignment.centerRight,
              fit: BoxFit.scaleDown,
              child: Text(
                '${entry.totalScore}点',
                style: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 68,
            child: FittedBox(
              alignment: Alignment.centerRight,
              fit: BoxFit.scaleDown,
              child: Text(
                '¥${_formatYen(earnedYen)}',
                style: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.tertiary,
                ),
              ),
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

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: scheme.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDateKey(String dateKey) {
  final parts = dateKey.split('-');
  if (parts.length != 3) return dateKey;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || day == null) return dateKey;
  return '$month/$day';
}

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
