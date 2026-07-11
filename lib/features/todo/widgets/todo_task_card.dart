import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/features/timer/model/task_sheet_result.dart';
import 'package:task_manager/features/timer/providers/timer_providers.dart';
import 'package:task_manager/features/timer/view/timer_lock_launcher.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/features/todo/widgets/todo_task_detail_sheet.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/prediction_chip_sheet.dart';

/// ToDo 1件を表示するカード。長押しでドラッグ、タップで詳細シート。
class TodoTaskCard extends ConsumerWidget {
  const TodoTaskCard({super.key, required this.task});

  final CalendarTask task;

  /// シートで「スタート」/「ポモドーロ」が押された場合、安定した context で
  /// ロック画面を起動する（シート自身はタイマー開始処理を行わない）。
  /// home_screen と同じ順序: 既存タイマー確認→チップシート→宣言の永続化→launcher。
  /// チップシートを出すのは未宣言タスクの初回スタートのみ
  /// （既存タイマーがあれば launcher がそちらを再開するためスキップ。宣言済みなら
  /// 宣言値で即スタートし、途中保存→閉じる→再スタート時に再度聞かない）。
  Future<void> _openDetailSheet(BuildContext context, WidgetRef ref) async {
    final result = await showTodoTaskDetailSheet(context: context, task: task);
    if ((result != TaskSheetResult.startTimer &&
            result != TaskSheetResult.startPomodoro) ||
        !context.mounted) {
      return;
    }

    final hasActiveTimer = ref.read(activeTimerStreamProvider).value != null;
    final declared = declaredPredictedMinutes(task);
    final int predictedMinutesForLaunch;
    if (hasActiveTimer) {
      predictedMinutesForLaunch = task.estimatedMinutes ?? 0;
    } else if (declared != null) {
      predictedMinutesForLaunch = declared;
    } else {
      final chosen = await showPredictionChipSheet(
        context,
        ref: ref,
        highlighted: null,
      );
      if (chosen == null || !context.mounted) return; // キャンセル＝開始の中断
      unawaited(
        ref
            .read(calendarTaskSyncRepositoryProvider)
            .saveDeclaredPrediction(taskId: task.id, minutes: chosen)
            .catchError((Object e) {
          if (context.mounted) {
            showAppSnackBar(
              context,
              SnackBar(content: Text('予測の保存に失敗しました: $e')),
            );
          }
        }),
      );
      predictedMinutesForLaunch = chosen;
    }

    if (result == TaskSheetResult.startPomodoro) {
      await TimerLockLauncher.openForPomodoro(
        context,
        ref,
        task: task,
        predictedMinutes: predictedMinutesForLaunch,
      );
      return;
    }
    await TimerLockLauncher.openForStart(
      context,
      ref,
      task: task,
      predictedMinutes: predictedMinutesForLaunch,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final cardContent = Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetailSheet(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            task.title,
            style: text.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );

    // 実際のカード幅を feedback にも反映させるために LayoutBuilder で包む
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 180.0;
        return LongPressDraggable<CalendarTask>(
          data: task,
          delay: const Duration(milliseconds: 300),
          dragAnchorStrategy: childDragAnchorStrategy,
          onDragStarted: () =>
              ref.read(draggingTodoProvider.notifier).setDragging(task),
          onDragEnd: (_) =>
              ref.read(draggingTodoProvider.notifier).setDragging(null),
          onDraggableCanceled: (_, _) =>
              ref.read(draggingTodoProvider.notifier).setDragging(null),
          onDragCompleted: () =>
              ref.read(draggingTodoProvider.notifier).setDragging(null),
          feedback: Transform.scale(
            scale: 1.03,
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: width,
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  color: scheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      task.title,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: cardContent),
          child: cardContent,
        );
      },
    );
  }
}
