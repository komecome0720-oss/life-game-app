import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:task_manager/features/timer/model/pomodoro_run.dart';

/// 計測中タイマーの永続化モデル（`users/{uid}/active_timer/current` 単一ドキュメント）。
///
/// 同時に1つのみ存在を保証する。`startedAtUtc` が null なら一時停止中、
/// 非 null なら計測中（実時間ベースで経過を計算するため、アプリ停止中も進む）。
///
/// [pomodoro] が非null ならポモドーロ実行中を表す。その場合、通常タイマー用の
/// `startedAtUtc`/`accumulatedSeconds` は使用しない（0/nullのまま）。
/// 既存フィールドの意味は通常タイマーでは完全に不変
/// （後方互換：`pomodoro` キーが無い既存docは通常タイマーとして扱う）。
@immutable
class ActiveTimer {
  const ActiveTimer({
    required this.taskId,
    required this.isTodo,
    required this.taskTitle,
    required this.predictedMinutes,
    required this.startedAtUtc,
    required this.accumulatedSeconds,
    required this.updatedAtUtc,
    this.pomodoro,
    this.quickStart = false,
  });

  final String taskId;
  final bool isTodo;

  /// タスク削除時のフォールバック表示用。
  final String taskTitle;
  final int predictedMinutes;

  /// null = 一時停止中。
  final DateTime? startedAtUtc;
  final int accumulatedSeconds;
  final DateTime updatedAtUtc;

  /// null = 通常タイマー。非null = ポモドーロ実行中。
  final PomodoroRun? pomodoro;

  /// クイックスタート（FAB長押しからの起動）で作られたタスクかどうか。
  final bool quickStart;

  bool get isRunning => startedAtUtc != null;

  /// 現在時刻 [now] における経過秒数（実時間ベース）。
  /// 端末時刻の巻き戻り等で負値にならないよう 0 にクランプする。
  int elapsedSeconds(DateTime now) {
    if (!isRunning) return accumulatedSeconds;
    final running = now.toUtc().difference(startedAtUtc!).inSeconds;
    return accumulatedSeconds + (running < 0 ? 0 : running);
  }

  ActiveTimer copyWith({
    String? taskId,
    bool? isTodo,
    String? taskTitle,
    int? predictedMinutes,
    DateTime? startedAtUtc,
    bool clearStartedAt = false,
    int? accumulatedSeconds,
    DateTime? updatedAtUtc,
    PomodoroRun? pomodoro,
    bool clearPomodoro = false,
    bool? quickStart,
  }) {
    return ActiveTimer(
      taskId: taskId ?? this.taskId,
      isTodo: isTodo ?? this.isTodo,
      taskTitle: taskTitle ?? this.taskTitle,
      predictedMinutes: predictedMinutes ?? this.predictedMinutes,
      startedAtUtc:
          clearStartedAt ? null : (startedAtUtc ?? this.startedAtUtc),
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      pomodoro: clearPomodoro ? null : (pomodoro ?? this.pomodoro),
      quickStart: quickStart ?? this.quickStart,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'taskId': taskId,
      'isTodo': isTodo,
      'taskTitle': taskTitle,
      'predictedMinutes': predictedMinutes,
      'startedAtUtc':
          startedAtUtc == null ? null : Timestamp.fromDate(startedAtUtc!),
      'accumulatedSeconds': accumulatedSeconds,
      'updatedAtUtc': Timestamp.fromDate(updatedAtUtc),
      'pomodoro': pomodoro?.toMap(),
      'quickStart': quickStart,
    };
  }

  factory ActiveTimer.fromMap(Map<String, dynamic> data) {
    final startedTs = data['startedAtUtc'] as Timestamp?;
    final updatedTs = data['updatedAtUtc'] as Timestamp?;
    return ActiveTimer(
      taskId: data['taskId'] as String? ?? '',
      isTodo: data['isTodo'] as bool? ?? false,
      taskTitle: data['taskTitle'] as String? ?? '',
      predictedMinutes: (data['predictedMinutes'] as num?)?.toInt() ?? 0,
      startedAtUtc: startedTs?.toDate(),
      accumulatedSeconds: (data['accumulatedSeconds'] as num?)?.toInt() ?? 0,
      updatedAtUtc: updatedTs?.toDate() ?? DateTime.now().toUtc(),
      pomodoro:
          PomodoroRun.fromMap(data['pomodoro'] as Map<String, dynamic>?),
      quickStart: data['quickStart'] as bool? ?? false,
    );
  }
}
