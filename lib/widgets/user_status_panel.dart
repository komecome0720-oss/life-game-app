import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/prediction_accuracy/model/prediction_accuracy_config.dart';
import 'package:task_manager/features/prediction_accuracy/providers/prediction_accuracy_providers.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';
import 'package:task_manager/features/user_settings/view/user_settings_screen.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';

class UserStatusPanel extends ConsumerWidget {
  const UserStatusPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uState = ref.watch(userSettingsProvider);
    final settings = uState.settings;
    final isFirstLoad = uState.isLoading && _isDefault(settings);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isFirstLoad
            ? null
            : () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const UserSettingsScreen(),
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ステータス',
                style: text.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              if (isFirstLoad)
                ...List.generate(
                  4,
                  (_) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: scheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                statusLine(
                  Icons.badge_outlined,
                  '名前',
                  settings.displayName.isEmpty ? '—' : settings.displayName,
                  text,
                ),
                UserStatusLevelLine(settings: settings),
                statusLine(
                  Icons.savings_outlined,
                  '所持金',
                  '¥${_fmt(settings.totalEarned)}',
                  text,
                ),
                const _PredictionAccuracyLine(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _isDefault(UserSettings s) {
    return s.displayName.isEmpty &&
        s.level == 1 &&
        s.totalEarned == 0 &&
        s.monthlyBudget == 0;
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
}

/// ステータスパネル内の1行（アイコン＋ラベル＋値）。[UserStatusPanel] と
/// [_PredictionAccuracyLine] で共有する。
Widget statusLine(IconData icon, String label, String value, TextTheme text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: text.bodySmall,
          maxLines: 1,
          softWrap: false,
        ),
        Expanded(
          child: Text(
            value,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    ),
  );
}

class UserStatusLevelLine extends StatelessWidget {
  const UserStatusLevelLine({super.key, required this.settings});

  final UserSettings settings;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = settings.levelProgress;
    final valueStyle = text.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.trending_up, size: 16),
              const SizedBox(width: 6),
              Text(
                'Lv.${p.level}',
                style: valueStyle,
                maxLines: 1,
                softWrap: false,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '次まであと${p.remainingToNext}',
                    style: text.labelSmall?.copyWith(color: scheme.outline),
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: p.fraction, minHeight: 4),
          ),
        ],
      ),
    );
  }
}

class _PredictionAccuracyLine extends ConsumerWidget {
  const _PredictionAccuracyLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(predictionAccuracyStatsProvider).asData?.value;
    final percent = stats?.percentRounded;
    final title = stats?.title;
    final measuringRemainder = stats?.measuringRemainder;
    final windowCount = stats?.windowCount ?? 0;
    final percentText = percent == null
        ? '—'
        : '${percent >= 0 ? '+' : ''}$percent%';
    // 対象30件未満のコールドスタートは称号の右に「直近○件」と件数を明示する（確定仕様13）。
    final showWindowCount =
        percent != null && windowCount < PredictionAccuracyConfig.rollingWindowSize;
    // 称号行：件数不足（悪い側・ビビリ系）は中立の「計測中」表示（確定仕様12）。
    final titleText = title ??
        (measuringRemainder != null ? '計測中（あと$measuringRemainder件）' : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        statusLine(Icons.schedule, '時間予測精度', percentText, text),
        if (titleText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titleText,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showWindowCount) ...[
                    const SizedBox(width: 6),
                    Text(
                      '（直近$windowCount件）',
                      style: text.labelSmall?.copyWith(color: scheme.outline),
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
