import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/features/economy/model/reward_calculator.dart';
import 'package:task_manager/features/economy/viewmodel/economy_fast_complete_service.dart';
import 'package:task_manager/features/roulette/model/roulette_outcome.dart';
import 'package:task_manager/features/roulette/providers/roulette_providers.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';

/// タスク完了時に TaskCompletionScreen へ渡す一式。
class CompletionOutcome {
  const CompletionOutcome({
    required this.taskTitle,
    required this.rewardYen,
    required this.balanceBeforeYen,
    required this.balanceAfterYen,
    required this.outcome,
    required this.cumulativeTaskCountBefore,
    required this.cumulativeTaskCountAfter,
    required this.predictedMinutes,
    required this.actualMinutes,
  });

  final String taskTitle;
  final int rewardYen;
  final int balanceBeforeYen;
  final int balanceAfterYen;
  final RouletteOutcome? outcome;
  final int cumulativeTaskCountBefore;
  final int cumulativeTaskCountAfter;
  final int predictedMinutes;
  final int? actualMinutes;
}

/// 保存・完了ロジックをタスク種別（ToDo/カレンダー）に依存せず実行する Riverpod サービス。
/// コールバックに依存しないため、ロック画面・各シートの双方から共通利用できる。
class TimerActions {
  TimerActions(this._ref);

  final Ref _ref;

  /// 時間単価ベースで報酬を算出する。単価未設定時は [fallbackYen] にフォールバック。
  int calcReward({
    required double hourlyRate,
    required int minutes,
    required int fallbackYen,
  }) {
    if (hourlyRate > 0 && minutes > 0) {
      return rewardYenFor(hourlyRate: hourlyRate, minutes: minutes);
    }
    return fallbackYen;
  }

  /// 未了のまま進捗（見込み・実績分）だけを保存する。
  /// タスク削除済み等の失敗は例外を握って false を返す。
  Future<bool> saveProgress({
    required String taskId,
    required int predictedMinutes,
    required int actualMinutes,
  }) async {
    try {
      await _ref.read(calendarTaskSyncRepositoryProvider).saveProgress(
            taskId: taskId,
            predictedMinutes: predictedMinutes,
            actualMinutes: actualMinutes,
          );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 完了時のカレンダー配置を実績ベースに置き直し、実際に完了させる taskId と
  /// 精度除外用の predicted 上書き値を返す。
  /// 日またぎは完了日0:00に丸める（表示のみ、分数は保持）。
  /// minutesForPlacement は呼び出し側で actualMinutes ?? predictedMinutes を渡す（>0前提だが
  /// null 安全のためこの形。UI層で実績必須を担保済み）。
  Future<({String taskId, int? predictedOverride})> placeForCompletion({
    required String taskId,
    required bool isTodo,
    required bool isAllDay,
    required String title,
    required int minutesForPlacement,
    String? colorId,
  }) async {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    var start = now.subtract(Duration(minutes: minutesForPlacement));
    if (start.isBefore(dayStart)) start = dayStart; // 日またぎ丸め（仕様5）
    final calRepo = _ref.read(calendarTaskSyncRepositoryProvider);
    if (isAllDay) {
      // 原本の終日予定は無変更・未完了のまま。新ブロックだけ生成して完了させる。
      final newId = await calRepo.createTaskFull(
        title: title,
        start: start,
        end: now,
        colorId: colorId,
      );
      return (taskId: newId, predictedOverride: 0); // predicted=0 で精度統計から除外
    }
    if (isTodo) {
      // 現状どおり todoRepository を使う（リポジトリ切替なし＝既存テスト温存）。
      // convertToCalendarEvent 側で repositioned:true を立てる。
      await _ref.read(todoRepositoryProvider).convertToCalendarEvent(
            taskId: taskId,
            start: start,
            end: now,
          );
      return (taskId: taskId, predictedOverride: null);
    }
    // 時間指定タスク：その場で start/end 上書き＋repositioned:true。
    await calRepo.moveTaskById(taskId: taskId, newStart: start, newEnd: now);
    return (taskId: taskId, predictedOverride: null);
  }

  /// タスクを完了させる（報酬付与 → ルーレット抽選）。
  /// カレンダー配置は [placeForCompletion] により実績ベースへ置き直してから完了させる。
  /// 失敗時（報酬付与が適用されなかった場合を含む）は null を返す。
  Future<CompletionOutcome?> complete({
    required CalendarTask task,
    required int predictedMinutes,
    required int? actualMinutes,
  }) async {
    final settings = _ref.read(userSettingsProvider).settings;
    final minutesForReward = actualMinutes ?? predictedMinutes;
    final rewardYen = calcReward(
      hourlyRate: settings.taskHourlyRate,
      minutes: minutesForReward,
      fallbackYen: task.rewardYen,
    );

    try {
      final placement = await placeForCompletion(
        taskId: task.id,
        isTodo: task.isTodo,
        isAllDay: task.isAllDay,
        title: task.title,
        minutesForPlacement: actualMinutes ?? predictedMinutes,
        colorId: task.colorId,
      );

      final result = await _ref
          .read(economyFastCompleteServiceProvider)
          .completeTaskFast(
            taskId: placement.taskId,
            title: task.title,
            rewardYen: rewardYen,
            predictedMinutes: placement.predictedOverride ?? predictedMinutes,
            actualMinutes: actualMinutes,
          );
      if (!result.applied) return null;

      RouletteOutcome? outcome;
      try {
        outcome = await _ref.read(rouletteServiceProvider).spin(
              completionId: placement.taskId,
              settings: settings,
            );
      } catch (_) {
        outcome = null;
      }

      return CompletionOutcome(
        taskTitle: task.title,
        rewardYen: rewardYen,
        balanceBeforeYen: result.balanceBeforeYen,
        balanceAfterYen: result.balanceAfterYen,
        outcome: outcome,
        cumulativeTaskCountBefore: result.cumulativeTaskCountBefore,
        cumulativeTaskCountAfter: result.cumulativeTaskCountAfter,
        predictedMinutes: predictedMinutes,
        actualMinutes: actualMinutes,
      );
    } catch (_) {
      return null;
    }
  }
}

final timerActionsProvider = Provider<TimerActions>((ref) => TimerActions(ref));
