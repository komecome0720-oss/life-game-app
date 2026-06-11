import 'package:flutter/material.dart';
import 'package:task_manager/features/health/model/health_log.dart';

/// 合計点数カード（100点満点）
class TotalScoreCard extends StatelessWidget {
  const TotalScoreCard({super.key, required this.log});
  final HealthLog log;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return _SummaryCard(
      icon: Icons.favorite,
      title: '合計点数',
      accentColor: scheme.primary,
      trailing: null,
      value: RichText(
        text: TextSpan(
          style: text.bodyMedium?.copyWith(height: 1),
          children: [
            TextSpan(
              text: '${log.totalScore}',
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
                height: 1,
              ),
            ),
            const TextSpan(text: ' / 100'),
          ],
        ),
      ),
      footer: Align(
        alignment: Alignment.topLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (log.totalScore / 100).clamp(0, 1),
            minHeight: 5,
            backgroundColor: scheme.surfaceContainerHighest,
            color: scheme.tertiary,
          ),
        ),
      ),
    );
  }
}

/// 合計金額カード（「?」ヘルプ付き）
class TotalEarningsCard extends StatelessWidget {
  const TotalEarningsCard({
    super.key,
    required this.log,
    required this.onHelpTap,
  });

  final HealthLog log;
  final VoidCallback onHelpTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return _SummaryCard(
      icon: Icons.savings_outlined,
      title: '獲得金額',
      accentColor: scheme.primary,
      trailing: IconButton(
        tooltip: '計算方法',
        icon: const Icon(Icons.help_outline, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
        onPressed: onHelpTap,
      ),
      value: Text(
        '¥${_fmt(log.provisionalEarnedYen)}',
        style: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.tertiary,
          height: 1,
        ),
      ),
      footer: Text(
        log.isFinalized ? '確定済み' : '本日暫定',
        style: text.labelSmall?.copyWith(height: 1),
      ),
    );
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.accentColor,
    required this.value,
    required this.footer,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Color accentColor;
  final Widget value;
  final Widget footer;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 18,
              child: Row(
                children: [
                  Icon(icon, size: 16, color: accentColor),
                  const SizedBox(width: 6),
                  Text(title, style: text.labelSmall),
                  const Spacer(),
                  trailing ?? const SizedBox.shrink(),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 30,
              child: Align(alignment: Alignment.topLeft, child: value),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 14,
              child: Align(alignment: Alignment.topLeft, child: footer),
            ),
          ],
        ),
      ),
    );
  }
}
