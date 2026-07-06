import 'package:flutter/foundation.dart';
import 'package:task_manager/features/timer/model/pomodoro_run.dart';

/// ポモドーロの1フェーズの種別。
enum PomodoroPhaseType {
  work,
  shortBreak,
  longBreak,
}

/// ある時刻における実効フェーズの状態（Firestore に依存しない純データ）。
@immutable
class PomodoroPhaseState {
  const PomodoroPhaseState({
    required this.phaseIndex,
    required this.type,
    required this.setNumber,
    required this.phaseLengthSeconds,
    required this.elapsedSeconds,
  });

  /// 実効的な（catch-up 後の）絶対フェーズ番号。
  final int phaseIndex;
  final PomodoroPhaseType type;

  /// セット番号（1始まり）。work・shortBreak は「これから/今の何セット目か」、
  /// longBreak は直前に終えたセット（=setCount）を表す。
  final int setNumber;
  final int phaseLengthSeconds;
  final int elapsedSeconds;

  /// 残り秒（負にならないようクランプ済み）。
  int get remainingSeconds {
    final r = phaseLengthSeconds - elapsedSeconds;
    return r < 0 ? 0 : r;
  }
}

/// PomodoroRun から実効フェーズ・完了クエスト数を導出する純ロジック。
///
/// 1周期 = 2*setCount フェーズ。`i = phaseIndex % (2*setCount)` として、
/// i が偶数 → クエスト（セット番号 = i/2 + 1）、i が奇数 → 休憩
/// （`i == 2*setCount - 1` のみ長休憩）。
class PomodoroSchedule {
  const PomodoroSchedule(this.run);

  final PomodoroRun run;

  int get _cycleLength => run.setCount * 2;

  /// 絶対フェーズ番号 [phaseIndex] の種別を返す。
  PomodoroPhaseType phaseTypeAt(int phaseIndex) {
    final i = phaseIndex % _cycleLength;
    if (i.isEven) return PomodoroPhaseType.work;
    return i == _cycleLength - 1
        ? PomodoroPhaseType.longBreak
        : PomodoroPhaseType.shortBreak;
  }

  /// 絶対フェーズ番号 [phaseIndex] のセット番号（1始まり）を返す。
  int setNumberAt(int phaseIndex) {
    final i = phaseIndex % _cycleLength;
    if (i.isEven) return i ~/ 2 + 1;
    if (i == _cycleLength - 1) return run.setCount;
    return i ~/ 2 + 1;
  }

  /// 絶対フェーズ番号 [phaseIndex] の長さ（秒）を返す。
  int phaseLengthSecondsAt(int phaseIndex) {
    switch (phaseTypeAt(phaseIndex)) {
      case PomodoroPhaseType.work:
        return run.workMinutes * 60;
      case PomodoroPhaseType.shortBreak:
        return run.shortBreakMinutes * 60;
      case PomodoroPhaseType.longBreak:
        return run.longBreakMinutes * 60;
    }
  }

  /// [phaseStartedAtUtc]==null（一時停止）なら現フェーズ内で凍結した状態を返す。
  /// running なら実時間から複数フェーズの catch-up を無制限に行い、実効状態を返す。
  PomodoroPhaseState currentPhase(DateTime now) {
    if (!run.isRunning) {
      final idx = run.phaseIndex;
      return PomodoroPhaseState(
        phaseIndex: idx,
        type: phaseTypeAt(idx),
        setNumber: setNumberAt(idx),
        phaseLengthSeconds: phaseLengthSecondsAt(idx),
        elapsedSeconds: run.phaseAccumulatedSeconds,
      );
    }

    final rawElapsed =
        now.toUtc().difference(run.phaseStartedAtUtc!).inSeconds;
    var elapsed = run.phaseAccumulatedSeconds + (rawElapsed < 0 ? 0 : rawElapsed);
    var idx = run.phaseIndex;
    var length = phaseLengthSecondsAt(idx);
    while (elapsed >= length) {
      elapsed -= length;
      idx += 1;
      length = phaseLengthSecondsAt(idx);
    }
    return PomodoroPhaseState(
      phaseIndex: idx,
      type: phaseTypeAt(idx),
      setNumber: setNumberAt(idx),
      phaseLengthSeconds: length,
      elapsedSeconds: elapsed,
    );
  }

  /// [run.phaseIndex] から [effectivePhaseIndex]（現時点までに実効的に到達した
  /// フェーズ）までの間に完了したクエスト（work フェーズ）の数を返す。
  /// 自動保存の差分計算に使う（`savedWorkPhases` との差分をとる）。
  int completedWorkPhasesUntil(int effectivePhaseIndex) {
    var count = 0;
    for (var i = run.phaseIndex; i < effectivePhaseIndex; i++) {
      if (phaseTypeAt(i) == PomodoroPhaseType.work) count += 1;
    }
    return count;
  }

  /// 現時点 [now] までに完了したクエスト数（catch-up 込み）。
  int completedWorkPhases(DateTime now) {
    final effective = currentPhase(now).phaseIndex;
    return completedWorkPhasesUntil(effective);
  }

  /// 復元専用：実時間から計算した実効フェーズが doc の phaseIndex を
  /// 1つ以上越えていた場合、**最大1フェーズ境界まで**しか進めない。
  /// 越えていなければ（同一フェーズ内）現状のまま返す。
  ///
  /// 越えた場合は「次フェーズの先頭・一時停止」の状態を返し、
  /// その1回分で完了したクエスト数（0 or 1）も返す。
  PomodoroRestoreResult restoreCappedToOnePhase(DateTime now) {
    final effective = currentPhase(now);
    if (effective.phaseIndex <= run.phaseIndex) {
      // 同一フェーズ内：通常どおり実行中/一時停止で復元。
      return PomodoroRestoreResult(run: run, completedWorkPhases: 0);
    }
    final nextIndex = run.phaseIndex + 1;
    final completed =
        phaseTypeAt(run.phaseIndex) == PomodoroPhaseType.work ? 1 : 0;
    final restored = run.copyWith(
      phaseIndex: nextIndex,
      clearPhaseStartedAt: true,
      phaseAccumulatedSeconds: 0,
      savedWorkPhases: run.savedWorkPhases + completed,
    );
    return PomodoroRestoreResult(
      run: restored,
      completedWorkPhases: completed,
    );
  }
}

/// [PomodoroSchedule.restoreCappedToOnePhase] の結果。
@immutable
class PomodoroRestoreResult {
  const PomodoroRestoreResult({
    required this.run,
    required this.completedWorkPhases,
  });

  /// 復元後の実行状態（越えていなければ元と同じインスタンス）。
  final PomodoroRun run;

  /// この復元操作で新たに完了したとみなすクエスト数（0 または 1）。
  final int completedWorkPhases;
}
