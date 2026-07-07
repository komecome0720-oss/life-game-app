import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';

/// やりかけの作業フェーズ（`PomodoroDay.carryWork`）。
/// タスク間で作業フェーズが凍結されたまま持ち越されるときに書かれる。
@immutable
class PomodoroCarryWork {
  const PomodoroCarryWork({
    required this.elapsedSeconds,
    required this.phaseLengthSeconds,
    required this.creditedMinutes,
  });

  /// フェーズ内の経過秒（前タスクまでの合計）。
  final int elapsedSeconds;

  /// フェーズ長スナップショット（設定変更に影響されない）。
  final int phaseLengthSeconds;

  /// このフェーズで既に先行タスク群へ実績加算済みの分数。
  final int creditedMinutes;

  Map<String, dynamic> toMap() => {
        'elapsedSeconds': elapsedSeconds,
        'phaseLengthSeconds': phaseLengthSeconds,
        'creditedMinutes': creditedMinutes,
      };

  static PomodoroCarryWork? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    return PomodoroCarryWork(
      elapsedSeconds: (data['elapsedSeconds'] as num?)?.toInt() ?? 0,
      phaseLengthSeconds: (data['phaseLengthSeconds'] as num?)?.toInt() ?? 0,
      creditedMinutes: (data['creditedMinutes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 未消化の休憩（`PomodoroDay.pendingBreak`）。[PomodoroCarryWork] と相互排他。
/// タスク間で休憩フェーズが実時間で消化され続けるときに書かれる。
@immutable
class PomodoroPendingBreak {
  const PomodoroPendingBreak({
    required this.isLong,
    required this.remainingSeconds,
    required this.sinceUtc,
  });

  final bool isLong;

  /// 書き込み時点の残秒。
  final int remainingSeconds;

  /// 書き込み時刻（次スタート時に `now - sinceUtc` を消化する）。
  final DateTime sinceUtc;

  Map<String, dynamic> toMap() => {
        'isLong': isLong,
        'remainingSeconds': remainingSeconds,
        'sinceUtc': Timestamp.fromDate(sinceUtc),
      };

  static PomodoroPendingBreak? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final ts = data['sinceUtc'] as Timestamp?;
    if (ts == null) return null;
    return PomodoroPendingBreak(
      isLong: data['isLong'] as bool? ?? false,
      remainingSeconds: (data['remainingSeconds'] as num?)?.toInt() ?? 0,
      sinceUtc: ts.toDate(),
    );
  }
}

/// `users/{uid}/pomodoro_days/{dateKey}`（dateKey = ローカル yyyy-MM-dd）の日次状態。
///
/// doc が無い日は「まっさら」（[empty] 相当）として扱う。開始位置の解決は
/// [resolveStart]（Firestore に依存しない純ロジック）が担う。
@immutable
class PomodoroDay {
  const PomodoroDay({
    required this.completedSetsToday,
    required this.cycleCompletedSets,
    this.carryWork,
    this.pendingBreak,
    required this.updatedAtUtc,
  });

  /// doc が無い日（まっさら）を表す初期値。
  factory PomodoroDay.empty(DateTime nowUtc) => PomodoroDay(
        completedSetsToday: 0,
        cycleCompletedSets: 0,
        updatedAtUtc: nowUtc,
      );

  /// 今日完走した作業フェーズ総数（表示用）。
  final int completedSetsToday;

  /// 現サイクル内の完走数。長休憩の完走で 0 にリセットされる。
  final int cycleCompletedSets;

  /// やりかけ作業フェーズ。null = なし。
  final PomodoroCarryWork? carryWork;

  /// 未消化の休憩。null = なし。[carryWork] と相互排他。
  final PomodoroPendingBreak? pendingBreak;

  final DateTime updatedAtUtc;

  PomodoroDay copyWith({
    int? completedSetsToday,
    int? cycleCompletedSets,
    PomodoroCarryWork? carryWork,
    bool clearCarryWork = false,
    PomodoroPendingBreak? pendingBreak,
    bool clearPendingBreak = false,
    DateTime? updatedAtUtc,
  }) {
    return PomodoroDay(
      completedSetsToday: completedSetsToday ?? this.completedSetsToday,
      cycleCompletedSets: cycleCompletedSets ?? this.cycleCompletedSets,
      carryWork: clearCarryWork ? null : (carryWork ?? this.carryWork),
      pendingBreak:
          clearPendingBreak ? null : (pendingBreak ?? this.pendingBreak),
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }

  Map<String, dynamic> toMap() => {
        'completedSetsToday': completedSetsToday,
        'cycleCompletedSets': cycleCompletedSets,
        'carryWork': carryWork?.toMap(),
        'pendingBreak': pendingBreak?.toMap(),
        'updatedAtUtc': Timestamp.fromDate(updatedAtUtc),
      };

  static PomodoroDay? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final updatedTs = data['updatedAtUtc'] as Timestamp?;
    return PomodoroDay(
      completedSetsToday: (data['completedSetsToday'] as num?)?.toInt() ?? 0,
      cycleCompletedSets: (data['cycleCompletedSets'] as num?)?.toInt() ?? 0,
      carryWork: PomodoroCarryWork.fromMap(
          data['carryWork'] as Map<String, dynamic>?),
      pendingBreak: PomodoroPendingBreak.fromMap(
          data['pendingBreak'] as Map<String, dynamic>?),
      updatedAtUtc: updatedTs?.toDate() ?? DateTime.now().toUtc(),
    );
  }

  /// 開始位置を解決する（純ロジック。Firestore に依存しない）。
  ///
  /// 設計原則: セット数・実績・作業秒は「フェーズ番号の範囲から導出」しない。
  /// ここでは「次のランがどこから始まるか」だけを決め、消化済みの
  /// [carryWork]/[pendingBreak] をクリアした [PomodoroDayStart.dayAfter] を返す
  /// （呼び出し元がこれを day doc へ書き戻す）。
  PomodoroDayStart resolveStart({
    required PomodoroSettings settings,
    required DateTime nowUtc,
  }) {
    final setCount = settings.setCount;
    var effectiveCycleCompletedSets = cycleCompletedSets;

    int posOf(int cycleCompleted) {
      final capped =
          cycleCompleted > setCount - 1 ? setCount - 1 : cycleCompleted;
      return capped < 0 ? 0 : capped;
    }

    final pendingBreak = this.pendingBreak;
    final carryWork = this.carryWork;

    final int startPhaseIndex;
    int? override;
    var carriedInSeconds = 0;
    var carriedInCreditedMinutes = 0;

    if (pendingBreak != null) {
      final rawConsumed = nowUtc.difference(pendingBreak.sinceUtc).inSeconds;
      final consumed = rawConsumed < 0 ? 0 : rawConsumed;
      final remaining = pendingBreak.remainingSeconds - consumed;
      if (remaining <= 0) {
        // 消化済み：長休憩ならサイクル位置をリセットする。
        if (pendingBreak.isLong) {
          effectiveCycleCompletedSets = 0;
        }
        startPhaseIndex = posOf(effectiveCycleCompletedSets) * 2;
        override = null;
      } else if (pendingBreak.isLong) {
        startPhaseIndex = 2 * setCount - 1;
        override = remaining;
      } else if (effectiveCycleCompletedSets >= 1) {
        // short break途中：設定縮小で置き場を失っていたら長休憩スロットへ振替。
        startPhaseIndex = effectiveCycleCompletedSets > setCount - 1
            ? 2 * setCount - 1
            : 2 * effectiveCycleCompletedSets - 1;
        override = remaining;
      } else {
        // 退化ケース（セット1完走前の短休憩。スキップ経由でのみ到達）：
        // サイクル上の置き場がないため破棄し、まっさら扱いで作業から開始する。
        startPhaseIndex = 0;
        override = null;
      }
    } else if (carryWork != null) {
      startPhaseIndex = posOf(effectiveCycleCompletedSets) * 2;
      override = carryWork.phaseLengthSeconds;
      carriedInSeconds = carryWork.elapsedSeconds;
      carriedInCreditedMinutes = carryWork.creditedMinutes;
    } else {
      startPhaseIndex = posOf(effectiveCycleCompletedSets) * 2;
      override = null;
    }

    assert(startPhaseIndex >= 0, 'startPhaseIndex must be >= 0');

    final dayAfter = copyWith(
      cycleCompletedSets: effectiveCycleCompletedSets,
      clearCarryWork: true,
      clearPendingBreak: true,
      updatedAtUtc: nowUtc,
    );

    return PomodoroDayStart(
      startPhaseIndex: startPhaseIndex,
      startPhaseLengthSecondsOverride: override,
      carriedInSeconds: carriedInSeconds,
      carriedInCreditedMinutes: carriedInCreditedMinutes,
      dayAfter: dayAfter,
    );
  }
}

/// [PomodoroDay.resolveStart] の結果。
@immutable
class PomodoroDayStart {
  const PomodoroDayStart({
    required this.startPhaseIndex,
    this.startPhaseLengthSecondsOverride,
    required this.carriedInSeconds,
    required this.carriedInCreditedMinutes,
    required this.dayAfter,
  });

  /// ランが開始する絶対フェーズ番号。
  final int startPhaseIndex;

  /// 開始フェーズの長さ上書き（null = 上書きなし＝設定どおりの長さ）。
  final int? startPhaseLengthSecondsOverride;

  /// 開始フェーズのうち前タスク群が消化済みの秒。
  final int carriedInSeconds;

  /// 開始フェーズのうち先行タスク群へ実績加算済みの分。
  final int carriedInCreditedMinutes;

  /// 消化後（carryWork/pendingBreak クリア・必要なら cycleCompletedSets
  /// リセット）に day doc へ書き戻すべき状態。
  final PomodoroDay dayAfter;
}
