import 'package:flutter/material.dart';
import 'package:task_manager/features/health/model/health_log.dart';
import 'package:task_manager/widgets/segmented_progress_bar.dart';

/// 合計点数カード（瞑想ON=100点満点 / OFF=80点満点）
class TotalScoreCard extends StatelessWidget {
  const TotalScoreCard({
    super.key,
    required this.log,
    this.maxActiveScore = 100,
  });
  final HealthLog log;

  /// 満点（瞑想ON=100 / OFF=80）。呼び出し元の設定に合わせて渡す。
  final int maxActiveScore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return _SummaryCard(
      icon: Icons.favorite,
      iconWidget: AnimatedHealthHeart(
        totalScore: log.totalScore,
        maxTotal: maxActiveScore,
      ),
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
            TextSpan(text: ' / $maxActiveScore'),
          ],
        ),
      ),
      footer: Align(
        alignment: Alignment.topLeft,
        child: TotalSegmentedProgressBar(
          totalScore: log.totalScore,
          maxTotal: maxActiveScore,
          height: 5,
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
    required this.dailyCapYen,
    required this.onHelpTap,
  });

  final HealthLog log;

  /// 満点なら貰える1日の満額（分母表示に使う）。
  final int dailyCapYen;
  final VoidCallback onHelpTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final earned = log.isFinalized
        ? log.finalizedEarnedYen
        : log.provisionalEarnedYen;
    return _SummaryCard(
      icon: Icons.savings_outlined,
      accentColor: scheme.primary,
      trailing: IconButton(
        tooltip: '計算方法',
        icon: const Icon(Icons.help_outline, size: 16),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
        onPressed: onHelpTap,
      ),
      value: RichText(
        text: TextSpan(
          style: text.bodyMedium?.copyWith(height: 1),
          children: [
            TextSpan(
              text: '¥${_fmt(earned)}',
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.tertiary,
                height: 1,
              ),
            ),
            TextSpan(text: ' / ${_fmt(dailyCapYen)}'),
          ],
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
    this.iconWidget,
    required this.accentColor,
    required this.value,
    required this.footer,
    this.trailing,
  });

  final IconData icon;
  final Widget? iconWidget;
  final Color accentColor;
  final Widget value;
  final Widget footer;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 26,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  iconWidget ?? Icon(icon, size: 20, color: accentColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: value,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 4),
                    trailing!,
                  ],
                ],
              ),
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
