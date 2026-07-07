import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/economy/data/economy_repository.dart';
import 'package:task_manager/features/economy/providers/economy_providers.dart';
import 'package:task_manager/features/economy/viewmodel/pending_task_completions_notifier.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/utils/app_messenger.dart';

/// `EconomyRepository.completeTask()` の呼び出し元3箇所（タイマー・ToDo詳細
/// シート・home_screen）を「ローカルファースト」化するサービス。
///
/// `completeTask()` 自体（Firestoreトランザクション・二重完了防止・残高加算・
/// 累計タスク数加算）は一切変更しない。ここでは「本物の書き込みを待たずに、
/// 常時listen中の `userSettingsProvider` のキャッシュ値から即座に仮の結果を
/// 組み立てて返す」ことで、呼び出し元の画面遷移（ルーレット表示）を高速化する。
class EconomyFastCompleteService {
  EconomyFastCompleteService(this._ref);

  final Ref _ref;

  Future<BalanceLedgerResult> completeTaskFast({
    required String taskId,
    required String title,
    required int rewardYen,
    required int predictedMinutes,
    required int? actualMinutes,
  }) async {
    final pendingState = _ref.read(pendingTaskCompletionsProvider);
    if (pendingState.inFlightTaskIds.contains(taskId)) {
      // 既に処理中（連打・別画面からの二重タップ）→ 何もしない。
      // 呼び出し元は既存の「二重完了防止（applied==false）」の分岐にそのまま乗る。
      return const BalanceLedgerResult(
        applied: false,
        deltaYen: 0,
        balanceBeforeYen: 0,
        balanceAfterYen: 0,
      );
    }

    final repo = _ref.read(economyRepositoryProvider);
    final settingsState = _ref.read(userSettingsProvider);

    // フォールバック条件は `isLoading || errorMessage != null`。
    // 初回スナップショットが来る前にストリームがエラーになった場合、
    // isLoading:false かつ settings がデフォルト（0円）のままになるため、
    // errorMessage も見て「誤って0円をキャッシュ値として使う」ことを防ぐ。
    if (settingsState.isLoading || settingsState.errorMessage != null) {
      return repo.completeTask(
        taskId: taskId,
        title: title,
        rewardYen: rewardYen,
        predictedMinutes: predictedMinutes,
        actualMinutes: actualMinutes,
      );
    }

    final cached = settingsState.settings;
    final before = cached.totalEarned + pendingState.pendingDeltaYen;
    final beforeCount =
        cached.cumulativeTaskCount + pendingState.pendingDeltaCount;
    final after = before + rewardYen;
    final afterCount = beforeCount + 1;

    final notifier = _ref.read(pendingTaskCompletionsProvider.notifier);
    notifier.begin(taskId, deltaYen: rewardYen, deltaCount: 1);

    unawaited(
      repo
          .completeTask(
            taskId: taskId,
            title: title,
            rewardYen: rewardYen,
            predictedMinutes: predictedMinutes,
            actualMinutes: actualMinutes,
          )
          .then((real) {
            notifier.end(taskId, deltaYen: rewardYen, deltaCount: 1);
            if (!real.applied) {
              _notifyFailure('タスク完了の反映に失敗しました（すでに完了済みの可能性があります）');
            }
          })
          .catchError((Object e) {
            notifier.end(taskId, deltaYen: rewardYen, deltaCount: 1);
            _notifyFailure('タスク完了の同期に失敗しました: $e');
          }),
    );

    return BalanceLedgerResult(
      applied: true,
      deltaYen: rewardYen,
      balanceBeforeYen: before,
      balanceAfterYen: after,
      cumulativeTaskCountBefore: beforeCount,
      cumulativeTaskCountAfter: afterCount,
    );
  }

  /// バックグラウンドの本物の処理が失敗/未反映だった場合の事後通知。
  /// 元の呼び出し元のcontextはすでに破棄されている可能性があるため、
  /// `navigatorKey`経由でルートの`ScaffoldMessenger`にアクセスする
  /// （新しいSnackBar関数は作らず、既存の`showAppSnackBar()`をそのまま使う）。
  void _notifyFailure(String message) {
    final ctx = navigatorKey.currentState?.context;
    if (ctx == null) return;
    showAppSnackBar(ctx, SnackBar(content: Text(message)), blocking: false);
  }
}

final economyFastCompleteServiceProvider = Provider<EconomyFastCompleteService>(
  (ref) => EconomyFastCompleteService(ref),
);
