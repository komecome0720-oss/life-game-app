import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/health/model/health_category.dart';
import 'package:task_manager/features/health/viewmodel/health_detail_viewmodel.dart';
import 'package:task_manager/features/health/widgets/health_history_section.dart';
import 'package:task_manager/features/health/widgets/health_item_row.dart';
import 'package:task_manager/features/health/widgets/total_cards.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/message_guard.dart';

class HealthDetailScreen extends ConsumerWidget {
  const HealthDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(healthDetailViewModelProvider);
    final settings = ref.watch(userSettingsProvider).settings;

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

    return Scaffold(
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
                        child: _LockBanner(isFinalized: state.log.isFinalized),
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
                          Expanded(child: TotalScoreCard(log: state.log)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TotalEarningsCard(
                              log: state.log,
                              onHelpTap: () => _showHelpDialog(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const HealthHistorySection(),
                    const SizedBox(height: 16),
                  ],
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
          '100点満点 = 毎日１００点の生活を送れば、寿命は10年伸びると仮定しています。\n'
          '80年の人生の1/8 = 10年分に相当。\n'
          '1日に換算すると24時間の1/8 = 3時間分の時間単価を獲得できます。\n\n'
          '例）時間単価3,000円/h の場合、100点 → 9,000円',
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
  const _LockBanner({required this.isFinalized});
  final bool isFinalized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              isFinalized ? '本日分は確定済みのため編集できません。' : '日付が変わったため編集できません。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
