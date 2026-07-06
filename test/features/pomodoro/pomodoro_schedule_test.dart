import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_schedule.dart';
import 'package:task_manager/features/timer/model/pomodoro_run.dart';

PomodoroRun _run({
  int workMinutes = 25,
  int shortBreakMinutes = 5,
  int setCount = 4,
  int longBreakMinutes = 15,
  int phaseIndex = 0,
  DateTime? phaseStartedAtUtc,
  int phaseAccumulatedSeconds = 0,
  int savedWorkPhases = 0,
  int baseActualMinutes = 0,
}) {
  return PomodoroRun(
    workMinutes: workMinutes,
    shortBreakMinutes: shortBreakMinutes,
    setCount: setCount,
    longBreakMinutes: longBreakMinutes,
    bgmWork: 'waves',
    bgmShortBreak: 'river',
    bgmLongBreak: 'birds',
    soundWorkStart: 'drum',
    soundShortBreakStart: 'bell',
    soundLongBreakStart: 'trumpet',
    phaseIndex: phaseIndex,
    phaseStartedAtUtc: phaseStartedAtUtc,
    phaseAccumulatedSeconds: phaseAccumulatedSeconds,
    savedWorkPhases: savedWorkPhases,
    baseActualMinutes: baseActualMinutes,
  );
}

void main() {
  final t0 = DateTime.utc(2026, 7, 6, 10, 0, 0);

  group('phaseTypeAt / setNumberAt / phaseLengthSecondsAt', () {
    test('K=4: work/break の並びとセット番号、長休憩の位置', () {
      final schedule = PomodoroSchedule(_run(setCount: 4));
      // i: 0=work(set1) 1=short 2=work(set2) 3=short 4=work(set3) 5=short
      // 6=work(set4) 7=long -> 周期8
      expect(schedule.phaseTypeAt(0), PomodoroPhaseType.work);
      expect(schedule.setNumberAt(0), 1);
      expect(schedule.phaseTypeAt(1), PomodoroPhaseType.shortBreak);
      expect(schedule.phaseTypeAt(6), PomodoroPhaseType.work);
      expect(schedule.setNumberAt(6), 4);
      expect(schedule.phaseTypeAt(7), PomodoroPhaseType.longBreak);
      expect(schedule.setNumberAt(7), 4);
      // 次周へ
      expect(schedule.phaseTypeAt(8), PomodoroPhaseType.work);
      expect(schedule.setNumberAt(8), 1);

      expect(schedule.phaseLengthSecondsAt(0), 25 * 60);
      expect(schedule.phaseLengthSecondsAt(1), 5 * 60);
      expect(schedule.phaseLengthSecondsAt(7), 15 * 60);
    });

    test('K=1: 毎回長休憩（周期2）', () {
      final schedule = PomodoroSchedule(_run(setCount: 1));
      expect(schedule.phaseTypeAt(0), PomodoroPhaseType.work);
      expect(schedule.phaseTypeAt(1), PomodoroPhaseType.longBreak);
      expect(schedule.phaseTypeAt(2), PomodoroPhaseType.work);
      expect(schedule.setNumberAt(0), 1);
      expect(schedule.setNumberAt(1), 1);
      expect(schedule.setNumberAt(2), 1);
    });
  });

  group('currentPhase: フェーズ境界', () {
    test('work→break境界: ちょうどworkMinutes経過で次フェーズ(short break)へ', () {
      final run = _run(phaseIndex: 0, phaseStartedAtUtc: t0);
      final schedule = PomodoroSchedule(run);
      final now = t0.add(const Duration(minutes: 25));
      final state = schedule.currentPhase(now);
      expect(state.phaseIndex, 1);
      expect(state.type, PomodoroPhaseType.shortBreak);
      expect(state.elapsedSeconds, 0);
      expect(state.remainingSeconds, 5 * 60);
    });

    test('Kセット目のクエスト終了後は長休憩へ', () {
      final run = _run(phaseIndex: 6, phaseStartedAtUtc: t0); // set4のwork
      final schedule = PomodoroSchedule(run);
      final now = t0.add(const Duration(minutes: 25));
      final state = schedule.currentPhase(now);
      expect(state.phaseIndex, 7);
      expect(state.type, PomodoroPhaseType.longBreak);
    });

    test('長休憩→次周1セット目のworkへ無限ループ', () {
      final run = _run(phaseIndex: 7, phaseStartedAtUtc: t0); // 長休憩中
      final schedule = PomodoroSchedule(run);
      final now = t0.add(const Duration(minutes: 15));
      final state = schedule.currentPhase(now);
      expect(state.phaseIndex, 8);
      expect(state.type, PomodoroPhaseType.work);
      expect(state.setNumber, 1);
    });
  });

  group('currentPhase: catch-up（アプリ停止中の複数フェーズ進行）', () {
    test('2.5フェーズ分経過: work(25分)+short(5分)+work途中12.5分', () {
      final run = _run(phaseIndex: 0, phaseStartedAtUtc: t0);
      final schedule = PomodoroSchedule(run);
      // 25 + 5 + 12.5 = 42.5分
      final now = t0.add(const Duration(minutes: 42, seconds: 30));
      final state = schedule.currentPhase(now);
      expect(state.phaseIndex, 2); // work(set1)->short->work(set2)
      expect(state.type, PomodoroPhaseType.work);
      expect(state.setNumber, 2);
      expect(state.elapsedSeconds, 12 * 60 + 30);
    });

    test('completedWorkPhasesUntil: 2.5フェーズ進行で完了クエストは1つ', () {
      final run = _run(phaseIndex: 0, phaseStartedAtUtc: t0);
      final schedule = PomodoroSchedule(run);
      final now = t0.add(const Duration(minutes: 42, seconds: 30));
      final effective = schedule.currentPhase(now).phaseIndex;
      expect(schedule.completedWorkPhasesUntil(effective), 1);
      expect(schedule.completedWorkPhases(now), 1);
    });

    test('completedWorkPhases は単調増加する', () {
      final run = _run(phaseIndex: 0, phaseStartedAtUtc: t0);
      final schedule = PomodoroSchedule(run);
      final c1 = schedule.completedWorkPhases(t0.add(const Duration(minutes: 10)));
      final c2 = schedule.completedWorkPhases(t0.add(const Duration(minutes: 40)));
      final c3 = schedule.completedWorkPhases(t0.add(const Duration(hours: 3)));
      expect(c1, 0);
      expect(c2, 1);
      expect(c3, greaterThanOrEqualTo(c2));
    });
  });

  group('一時停止', () {
    test('phaseStartedAtUtc=null なら現フェーズ内で凍結する', () {
      final run = _run(
        phaseIndex: 2,
        phaseStartedAtUtc: null,
        phaseAccumulatedSeconds: 300,
      );
      final schedule = PomodoroSchedule(run);
      final state1 = schedule.currentPhase(t0);
      final state2 = schedule.currentPhase(t0.add(const Duration(hours: 5)));
      expect(state1.phaseIndex, 2);
      expect(state1.elapsedSeconds, 300);
      expect(state2.phaseIndex, 2);
      expect(state2.elapsedSeconds, 300);
    });

    test('再開後は継続して進行する', () {
      final resumedRun = _run(
        phaseIndex: 2,
        phaseStartedAtUtc: t0,
        phaseAccumulatedSeconds: 300,
      );
      final schedule = PomodoroSchedule(resumedRun);
      final state = schedule.currentPhase(t0.add(const Duration(minutes: 10)));
      expect(state.elapsedSeconds, 300 + 600);
    });
  });

  group('残り秒のクランプ', () {
    test('経過がフェーズ長を超えても remainingSeconds は0未満にならない', () {
      // currentPhase 自体が繰り上げるため、意図的に「凍結」経過で長さ超過を再現。
      final run = _run(
        phaseIndex: 0,
        phaseStartedAtUtc: null,
        phaseAccumulatedSeconds: 25 * 60 + 999,
      );
      final schedule = PomodoroSchedule(run);
      final state = schedule.currentPhase(t0);
      expect(state.remainingSeconds, 0);
    });
  });

  group('1分設定の端値', () {
    test('workMinutes=1, shortBreakMinutes=1 でも正しく進行する', () {
      final run = _run(
        workMinutes: 1,
        shortBreakMinutes: 1,
        setCount: 2,
        longBreakMinutes: 1,
        phaseIndex: 0,
        phaseStartedAtUtc: t0,
      );
      final schedule = PomodoroSchedule(run);
      final state = schedule.currentPhase(t0.add(const Duration(minutes: 3)));
      // work(1)->short(1)->work(2)->long(1) : 3分ちょうどでphaseIndex=3の先頭
      expect(state.phaseIndex, 3);
      expect(state.type, PomodoroPhaseType.longBreak);
      expect(state.elapsedSeconds, 0);
    });
  });

  group('restoreCappedToOnePhase（復元用の1フェーズ上限）', () {
    test('同一フェーズ内なら変化なし', () {
      final run = _run(phaseIndex: 0, phaseStartedAtUtc: t0);
      final schedule = PomodoroSchedule(run);
      final result =
          schedule.restoreCappedToOnePhase(t0.add(const Duration(minutes: 10)));
      expect(result.run.phaseIndex, 0);
      expect(result.run.isRunning, isTrue);
      expect(result.completedWorkPhases, 0);
    });

    test('8時間経過でも+1フェーズ・一時停止までしか進めない', () {
      final run = _run(phaseIndex: 0, phaseStartedAtUtc: t0);
      final schedule = PomodoroSchedule(run);
      final result =
          schedule.restoreCappedToOnePhase(t0.add(const Duration(hours: 8)));
      expect(result.run.phaseIndex, 1); // work(0)の次のフェーズまで
      expect(result.run.isRunning, isFalse);
      expect(result.run.phaseAccumulatedSeconds, 0);
      expect(result.completedWorkPhases, 1); // work→break境界を1回越えた
    });

    test('休憩フェーズを1つ越えて次のworkへ進む場合は完了クエスト0', () {
      final run = _run(phaseIndex: 1, phaseStartedAtUtc: t0); // short break中
      final schedule = PomodoroSchedule(run);
      final result =
          schedule.restoreCappedToOnePhase(t0.add(const Duration(hours: 2)));
      expect(result.run.phaseIndex, 2);
      expect(result.run.isRunning, isFalse);
      expect(result.completedWorkPhases, 0);
    });

    test('savedWorkPhasesが復元完了クエスト数ぶん加算される', () {
      final run = _run(
        phaseIndex: 0,
        phaseStartedAtUtc: t0,
        savedWorkPhases: 2,
      );
      final schedule = PomodoroSchedule(run);
      final result =
          schedule.restoreCappedToOnePhase(t0.add(const Duration(hours: 1)));
      expect(result.run.savedWorkPhases, 3);
    });

    test('一時停止中の実行状態はそのまま返る（越えない）', () {
      final run = _run(
        phaseIndex: 0,
        phaseStartedAtUtc: null,
        phaseAccumulatedSeconds: 100,
      );
      final schedule = PomodoroSchedule(run);
      final result = schedule.restoreCappedToOnePhase(t0);
      expect(result.run.phaseIndex, 0);
      expect(result.run.isRunning, isFalse);
      expect(result.completedWorkPhases, 0);
    });
  });
}
