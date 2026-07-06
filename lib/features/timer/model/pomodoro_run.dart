import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
  });

  /// 開始時点の設定スナップショットから新規実行状態を作る
  /// （phaseIndex=0＝1セット目のクエスト開始・実行中・時計ゼロ）。
  factory PomodoroRun.start({
    required PomodoroSettings settings,
    required int baseActualMinutes,
    required DateTime nowUtc,
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
      phaseIndex: 0,
      phaseStartedAtUtc: nowUtc,
      phaseAccumulatedSeconds: 0,
      savedWorkPhases: 0,
      baseActualMinutes: baseActualMinutes,
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

  /// ポモドーロ開始時点の「現状」値（保存は base + 完了数 で計算する）。
  final int baseActualMinutes;

  bool get isRunning => phaseStartedAtUtc != null;

  PomodoroRun copyWith({
    int? phaseIndex,
    DateTime? phaseStartedAtUtc,
    bool clearPhaseStartedAt = false,
    int? phaseAccumulatedSeconds,
    int? savedWorkPhases,
    int? baseActualMinutes,
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
    };
  }

  static PomodoroRun? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final phaseStartedTs = data['phaseStartedAtUtc'] as Timestamp?;
    return PomodoroRun(
      workMinutes: (data['workMinutes'] as num?)?.toInt() ??
          PomodoroSettings.defaultWorkMinutes,
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
      savedWorkPhases: (data['savedWorkPhases'] as num?)?.toInt() ?? 0,
      baseActualMinutes: (data['baseActualMinutes'] as num?)?.toInt() ?? 0,
    );
  }
}
