import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/health/model/health_category.dart';
import 'package:task_manager/features/health/viewmodel/health_detail_viewmodel.dart';
import 'package:task_manager/features/health/widgets/health_item_row.dart';
import 'package:task_manager/features/health/widgets/health_streak_calendar.dart';
import 'package:task_manager/features/health/widgets/total_cards.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/message_guard.dart';

class HealthDetailScreen extends ConsumerStatefulWidget {
  const HealthDetailScreen({super.key});

  @override
  ConsumerState<HealthDetailScreen> createState() => _HealthDetailScreenState();
}

class _HealthDetailScreenState extends ConsumerState<HealthDetailScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // バックグラウンド移行／終了時に、この滞在中の正味差分を1件だけ確定する。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      ref.read(healthDetailViewModelProvider.notifier).settlePendingLedger();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(healthDetailViewModelProvider);
    final settings = ref.watch(userSettingsProvider.select((s) => s.settings));

    ref.listen<HealthDetailState>(healthDetailViewModelProvider, (prev, next) {
      final msg = next.errorMessage;
      if (msg != null && msg.isNotEmpty && prev?.errorMessage != msg) {
        showAppSnackBar(
          context,
          SnackBar(
            content: Text(msg),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    });

    final editable = state.isEditableNow && !state.log.isFinalized;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        // 「戻る」時に、この滞在中の正味差分を冒険の記録へ1件だけ確定してから離脱。
        await ref
            .read(healthDetailViewModelProvider.notifier)
            .settlePendingLedger();
        if (!mounted) return;
        nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('健康管理')),
        body: MessageGuard(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!editable)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _LockBanner(
                          isFinalized: state.log.isFinalized,
                          // ロード失敗／未確認による編集ロックを「日付が変わった」と
                          // 誤解させないよう文言を分岐する。
                          isLoadFailure: !state.log.isFinalized &&
                              state.errorMessage != null,
                        ),
                      ),
                    for (final c in HealthCategory.values)
                      HealthItemRow(
                        category: c,
                        log: state.log,
                        settings: settings,
                        enabled: editable,
                      ),
                    const SizedBox(height: 4),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: TotalScoreCard(
                              log: state.log,
                              maxActiveScore: settings.maxActiveHealthScore,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TotalEarningsCard(
                              log: state.log,
                              dailyCapYen: settings.healthDailyCapYen,
                              onHelpTap: () => _showHelpDialog(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    HealthStreakCalendar(streakState: state.streakState),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Future<void> _showHelpDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('獲得金額の計算'),
        content: const Text(
          '健康を整えることは「1日3時間分の立派な仕事」。\n'
          '月のお小遣いのうち30%を健康の枠として確保し、固定30日で割った額が'
          '「1日満額」です（例：月予算30,000円 → 1日満額300円）。\n\n'
          '達成率（合計点 ÷ 満点）が40%未満の日は、その日の健康分は0円になります'
          '（没収はその日の健康分のみ。タスク報酬や前日までの残高には一切影響しません）。\n'
          '40%以上なら「1日満額 × 達成率」（四捨五入）を獲得できます。\n\n'
          '獲得額は深夜または次回起動時に確定し、所持金へ反映されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
}

class _LockBanner extends StatelessWidget {
  const _LockBanner({required this.isFinalized, this.isLoadFailure = false});
  final bool isFinalized;

  /// ロード失敗／未確認による編集ロック（日付境界とは無関係）かどうか。
  /// true の場合、「日付が変わった」ではなく通信状況を促す文言にする。
  final bool isLoadFailure;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String message;
    if (isFinalized) {
      message = '本日分は確定済みのため編集できません。';
    } else if (isLoadFailure) {
      message = '記録を読み込めませんでした。通信状況を確認してください（自動で再試行します）。';
    } else {
      message = '日付が変わったため編集できません。';
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_clock, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
