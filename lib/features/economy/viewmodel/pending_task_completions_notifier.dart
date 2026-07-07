import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';

/// タスク完了のローカルファースト化（`EconomyFastCompleteService`）で使う、
/// アプリ全体で共有する「処理中」state。
///
/// - `inFlightTaskIds`：バックグラウンドで本物の `completeTask()` を実行中の
///   taskId 集合。二重タップ（同一タスクをまたいだ別画面からの操作も含む）を
///   防ぐガードとして使う。
/// - `pendingDeltaYen` / `pendingDeltaCount`：まだ `userSettingsProvider` の
///   キャッシュに反映されていない（サーバー確定前の）加算予定分。連続で
///   タスクを完了したとき、2件目の「仮の残高」計算に1件目の未反映分を
///   足し込むために使う。
class PendingTaskCompletionsState {
  const PendingTaskCompletionsState({
    this.inFlightTaskIds = const <String>{},
    this.pendingDeltaYen = 0,
    this.pendingDeltaCount = 0,
  });

  final Set<String> inFlightTaskIds;
  final int pendingDeltaYen;
  final int pendingDeltaCount;

  PendingTaskCompletionsState copyWith({
    Set<String>? inFlightTaskIds,
    int? pendingDeltaYen,
    int? pendingDeltaCount,
  }) {
    return PendingTaskCompletionsState(
      inFlightTaskIds: inFlightTaskIds ?? this.inFlightTaskIds,
      pendingDeltaYen: pendingDeltaYen ?? this.pendingDeltaYen,
      pendingDeltaCount: pendingDeltaCount ?? this.pendingDeltaCount,
    );
  }
}

class PendingTaskCompletionsNotifier
    extends Notifier<PendingTaskCompletionsState> {
  @override
  PendingTaskCompletionsState build() {
    // ログイン/ログアウト/ユーザー切替でuidが変わったら build() が再実行され、
    // 前ユーザーの in-flight / pendingDelta が次ユーザーへ混入しないようにする
    // （userSettingsProvider と同じ考え方）。
    ref.watch(authStateProvider.select((async) => async.asData?.value?.uid));
    return const PendingTaskCompletionsState();
  }

  bool isInFlight(String taskId) => state.inFlightTaskIds.contains(taskId);

  /// 呼び出し前に [isInFlight] のチェックが済んでいる前提。
  /// 防御的に、既に登録済みなら何もしない（重複登録は想定しない）。
  void begin(String taskId, {required int deltaYen, required int deltaCount}) {
    if (state.inFlightTaskIds.contains(taskId)) return;
    state = state.copyWith(
      inFlightTaskIds: {...state.inFlightTaskIds, taskId},
      pendingDeltaYen: state.pendingDeltaYen + deltaYen,
      pendingDeltaCount: state.pendingDeltaCount + deltaCount,
    );
  }

  /// 未登録（uid切替でリセット済み等）なら何もしない。
  void end(String taskId, {required int deltaYen, required int deltaCount}) {
    if (!state.inFlightTaskIds.contains(taskId)) return;
    final updated = {...state.inFlightTaskIds}..remove(taskId);
    state = state.copyWith(
      inFlightTaskIds: updated,
      pendingDeltaYen: state.pendingDeltaYen - deltaYen,
      pendingDeltaCount: state.pendingDeltaCount - deltaCount,
    );
  }
}

final pendingTaskCompletionsProvider =
    NotifierProvider<PendingTaskCompletionsNotifier, PendingTaskCompletionsState>(
  PendingTaskCompletionsNotifier.new,
);
