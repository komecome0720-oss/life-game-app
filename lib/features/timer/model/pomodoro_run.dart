import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_day.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';

/// ポモドーロ実行状態（`ActiveTimer.pomodoro` フィールドの型）。
///
/// 開始時点の設定スナップショット（実行中に設定画面を変更しても現在の
/// 実行には影響しない）＋進行状態を1つのドキュメントで保持する。
/// フェーズの意味・catch-up 計算は `PomodoroSchedule`（純ロジック）が担う。
@immutable
class PomodoroRun {
  const PomodoroRun({
    required this.workMinutes,
    required this.shortBreakMinutes,
    required this.setCount,
    required this.longBreakMinutes,
    required this.bgmWork,
    required this.bgmShortBreak,
    required this.bgmLongBreak,
    required this.soundWorkStart,
    required this.soundShortBreakStart,
    required this.soundLongBreakStart,
    required this.phaseIndex,
    required this.phaseStartedAtUtc,
    required this.phaseAccumulatedSeconds,
    required this.savedWorkPhases,
    required this.baseActualMinutes,
    this.startPhaseIndex = 0,
    this.startPhaseLengthSecondsOverride,
    this.carriedInSeconds = 0,
    this.carriedInCreditedMinutes = 0,
    int? creditedMinutes,
    this.dateKey = '',
  }) : creditedMinutes = creditedMinutes ?? savedWorkPhases * workMinutes;

  /// 開始時点の設定スナップショットから新規実行状態を作る
  /// （既定では phaseIndex=0＝1セット目のクエスト開始・実行中・時計ゼロ）。
  ///
  /// [dayStart] を渡すと「1日通しセット」の開始位置（やりかけ作業フェーズの再開・
  /// 未消化休憩の消化）を反映する。渡さない場合は既定（1セット目の先頭）になる。
  factory PomodoroRun.start({
    required PomodoroSettings settings,
    required int baseActualMinutes,
    required DateTime nowUtc,
    PomodoroDayStart? dayStart,
    String dateKey = '',
  }) {
    return PomodoroRun(
      workMinutes: settings.workMinutes,
      shortBreakMinutes: settings.shortBreakMinutes,
      setCount: settings.setCount,
      longBreakMinutes: settings.longBreakMinutes,
      bgmWork: settings.bgmWork.id,
      bgmShortBreak: settings.bgmShortBreak.id,
      bgmLongBreak: settings.bgmLongBreak.id,
      soundWorkStart: settings.soundWorkStart.id,
      soundShortBreakStart: settings.soundShortBreakStart.id,
      soundLongBreakStart: settings.soundLongBreakStart.id,
      phaseIndex: dayStart?.startPhaseIndex ?? 0,
      phaseStartedAtUtc: nowUtc,
      phaseAccumulatedSeconds: dayStart?.carriedInSeconds ?? 0,
      savedWorkPhases: 0,
      baseActualMinutes: baseActualMinutes,
      startPhaseIndex: dayStart?.startPhaseIndex ?? 0,
      startPhaseLengthSecondsOverride:
          dayStart?.startPhaseLengthSecondsOverride,
      carriedInSeconds: dayStart?.carriedInSeconds ?? 0,
      carriedInCreditedMinutes: dayStart?.carriedInCreditedMinutes ?? 0,
      creditedMinutes: 0,
      dateKey: dateKey,
    );
  }

  // 開始時の設定スナップショット。
  final int workMinutes;
  final int shortBreakMinutes;
  final int setCount;
  final int longBreakMinutes;
  final String bgmWork;
  final String bgmShortBreak;
  final String bgmLongBreak;
  final String soundWorkStart;
  final String soundShortBreakStart;
  final String soundLongBreakStart;

  // 進行状態。
  /// 0起点の絶対フェーズ番号。
  final int phaseIndex;

  /// null = 一時停止中（現フェーズの時計）。
  final DateTime? phaseStartedAtUtc;
  final int phaseAccumulatedSeconds;

  /// 「現状」へ加算済みの完了クエスト数（自動保存の冪等性用）。
  final int savedWorkPhases;

  /// ポモドーロ開始時点の「現状」値（保存は base + creditedMinutes で計算する）。
  final int baseActualMinutes;

  // 「1日通しセット」用の追加フィールド（wire 後方互換：欠損時は既定値）。

  /// このランが開始した絶対フェーズ番号（1日通しセットの再開位置）。
  /// 既定 0 = 旧doc互換（従来どおり1セット目の先頭から）。
  final int startPhaseIndex;

  /// 開始フェーズ（[startPhaseIndex]）の長さ上書き（秒）。
  /// null = 上書きなし（設定どおりの長さ）。やりかけフェーズの再開時に使う。
  final int? startPhaseLengthSecondsOverride;

  /// 開始フェーズのうち前タスク群が消化済みの秒（やりかけフェーズ再開の続きから開始するため）。
  final int carriedInSeconds;

  /// 開始フェーズのうち先行タスク群へ実績加算済みの分（比例配分の控除に使う）。
  final int carriedInCreditedMinutes;

  /// このランでタスクへコミット済みの実績分（明示カウンタ）。
  /// セット数・作業秒はフェーズ番号の範囲から導出せず、常にこの値を真実とする
  /// （スキップは完走ではないため、savedWorkPhases とは独立に管理する）。
  final int creditedMinutes;

  /// このランが属する日（ローカル dateKey）。既定 '' は「now の dateKey」を表す。
  final String dateKey;

  bool get isRunning => phaseStartedAtUtc != null;

  PomodoroRun copyWith({
    int? phaseIndex,
    DateTime? phaseStartedAtUtc,
    bool clearPhaseStartedAt = false,
    int? phaseAccumulatedSeconds,
    int? savedWorkPhases,
    int? baseActualMinutes,
    int? startPhaseIndex,
    int? startPhaseLengthSecondsOverride,
    bool clearStartPhaseLengthSecondsOverride = false,
    int? carriedInSeconds,
    int? carriedInCreditedMinutes,
    int? creditedMinutes,
    String? dateKey,
  }) {
    return PomodoroRun(
      workMinutes: workMinutes,
      shortBreakMinutes: shortBreakMinutes,
      setCount: setCount,
      longBreakMinutes: longBreakMinutes,
      bgmWork: bgmWork,
      bgmShortBreak: bgmShortBreak,
      bgmLongBreak: bgmLongBreak,
      soundWorkStart: soundWorkStart,
      soundShortBreakStart: soundShortBreakStart,
      soundLongBreakStart: soundLongBreakStart,
      phaseIndex: phaseIndex ?? this.phaseIndex,
      phaseStartedAtUtc: clearPhaseStartedAt
          ? null
          : (phaseStartedAtUtc ?? this.phaseStartedAtUtc),
      phaseAccumulatedSeconds:
          phaseAccumulatedSeconds ?? this.phaseAccumulatedSeconds,
      savedWorkPhases: savedWorkPhases ?? this.savedWorkPhases,
      baseActualMinutes: baseActualMinutes ?? this.baseActualMinutes,
      startPhaseIndex: startPhaseIndex ?? this.startPhaseIndex,
      startPhaseLengthSecondsOverride: clearStartPhaseLengthSecondsOverride
          ? null
          : (startPhaseLengthSecondsOverride ??
              this.startPhaseLengthSecondsOverride),
      carriedInSeconds: carriedInSeconds ?? this.carriedInSeconds,
      carriedInCreditedMinutes:
          carriedInCreditedMinutes ?? this.carriedInCreditedMinutes,
      creditedMinutes: creditedMinutes ?? this.creditedMinutes,
      dateKey: dateKey ?? this.dateKey,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'workMinutes': workMinutes,
      'shortBreakMinutes': shortBreakMinutes,
      'setCount': setCount,
      'longBreakMinutes': longBreakMinutes,
      'bgmWork': bgmWork,
      'bgmShortBreak': bgmShortBreak,
      'bgmLongBreak': bgmLongBreak,
      'soundWorkStart': soundWorkStart,
      'soundShortBreakStart': soundShortBreakStart,
      'soundLongBreakStart': soundLongBreakStart,
      'phaseIndex': phaseIndex,
      'phaseStartedAtUtc': phaseStartedAtUtc == null
          ? null
          : Timestamp.fromDate(phaseStartedAtUtc!),
      'phaseAccumulatedSeconds': phaseAccumulatedSeconds,
      'savedWorkPhases': savedWorkPhases,
      'baseActualMinutes': baseActualMinutes,
      'startPhaseIndex': startPhaseIndex,
      'startPhaseLengthSecondsOverride': startPhaseLengthSecondsOverride,
      'carriedInSeconds': carriedInSeconds,
      'carriedInCreditedMinutes': carriedInCreditedMinutes,
      'creditedMinutes': creditedMinutes,
      'dateKey': dateKey,
    };
  }

  static PomodoroRun? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final phaseStartedTs = data['phaseStartedAtUtc'] as Timestamp?;
    final workMinutes = (data['workMinutes'] as num?)?.toInt() ??
        PomodoroSettings.defaultWorkMinutes;
    final savedWorkPhases = (data['savedWorkPhases'] as num?)?.toInt() ?? 0;
    return PomodoroRun(
      workMinutes: workMinutes,
      shortBreakMinutes: (data['shortBreakMinutes'] as num?)?.toInt() ??
          PomodoroSettings.defaultShortBreakMinutes,
      setCount: (data['setCount'] as num?)?.toInt() ??
          PomodoroSettings.defaultSetCount,
      longBreakMinutes: (data['longBreakMinutes'] as num?)?.toInt() ??
          PomodoroSettings.defaultLongBreakMinutes,
      bgmWork:
          data['bgmWork'] as String? ?? PomodoroSettings.defaultBgmWork.id,
      bgmShortBreak: data['bgmShortBreak'] as String? ??
          PomodoroSettings.defaultBgmShortBreak.id,
      bgmLongBreak: data['bgmLongBreak'] as String? ??
          PomodoroSettings.defaultBgmLongBreak.id,
      soundWorkStart: data['soundWorkStart'] as String? ??
          PomodoroSettings.defaultSoundWorkStart.id,
      soundShortBreakStart: data['soundShortBreakStart'] as String? ??
          PomodoroSettings.defaultSoundShortBreakStart.id,
      soundLongBreakStart: data['soundLongBreakStart'] as String? ??
          PomodoroSettings.defaultSoundLongBreakStart.id,
      phaseIndex: (data['phaseIndex'] as num?)?.toInt() ?? 0,
      phaseStartedAtUtc: phaseStartedTs?.toDate(),
      phaseAccumulatedSeconds:
          (data['phaseAccumulatedSeconds'] as num?)?.toInt() ?? 0,
      savedWorkPhases: savedWorkPhases,
      baseActualMinutes: (data['baseActualMinutes'] as num?)?.toInt() ?? 0,
      startPhaseIndex: (data['startPhaseIndex'] as num?)?.toInt() ?? 0,
      startPhaseLengthSecondsOverride:
          (data['startPhaseLengthSecondsOverride'] as num?)?.toInt(),
      carriedInSeconds: (data['carriedInSeconds'] as num?)?.toInt() ?? 0,
      carriedInCreditedMinutes:
          (data['carriedInCreditedMinutes'] as num?)?.toInt() ?? 0,
      // 旧doc（creditedMinutes キー無し）は savedWorkPhases*workMinutes で
      // 補完し、新実績計算（base + creditedMinutes）が旧計算と同値になるようにする。
      creditedMinutes: (data['creditedMinutes'] as num?)?.toInt() ??
          savedWorkPhases * workMinutes,
      dateKey: data['dateKey'] as String? ?? '',
    );
  }
}
