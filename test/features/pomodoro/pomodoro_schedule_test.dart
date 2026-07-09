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
  int startPhaseIndex = 0,
  int? startPhaseLengthSecondsOverride,
  int carriedInSeconds = 0,
  int carriedInCreditedMinutes = 0,
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
    startPhaseIndex: startPhaseIndex,
    startPhaseLengthSecondsOverride: startPhaseLengthSecondsOverride,
    carriedInSeconds: carriedInSeconds,
    carriedInCreditedMinutes: carriedInCreditedMinutes,
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

  group('phaseLengthSecondsAt: 開始フェーズの長さ上書き', () {
    test('startPhaseIndexかつoverride指定ありならそちらを優先する', () {
      final run = _run(
        phaseIndex: 0,
        startPhaseIndex: 0,
        startPhaseLengthSecondsOverride: 300,
      );
      final schedule = PomodoroSchedule(run);
      expect(schedule.phaseLengthSecondsAt(0), 300);
      // 他のフェーズは通常どおり（設定値）。
      expect(schedule.phaseLengthSecondsAt(1), 5 * 60);
    });

    test('override が null なら通常どおりの長さ', () {
      final run = _run(phaseIndex: 0, startPhaseIndex: 0);
      final schedule = PomodoroSchedule(run);
      expect(schedule.phaseLengthSecondsAt(0), 25 * 60);
    });
  });

  group('inProgressSessionSeconds', () {
    test('開始フェーズ（work）: carriedInSecondsを差し引く', () {
      final run = _run(startPhaseIndex: 0, carriedInSeconds: 300);
      final schedule = PomodoroSchedule(run);
      final state = PomodoroPhaseState(
        phaseIndex: 0,
        type: PomodoroPhaseType.work,
        setNumber: 1,
        phaseLengthSeconds: 1500,
        elapsedSeconds: 400,
      );
      expect(schedule.inProgressSessionSeconds(state), 100);
    });

    test('通常フェーズ（開始フェーズでない）: そのまま返る', () {
      final run = _run(startPhaseIndex: 0, carriedInSeconds: 300);
      final schedule = PomodoroSchedule(run);
      final state = PomodoroPhaseState(
        phaseIndex: 2,
        type: PomodoroPhaseType.work,
        setNumber: 2,
        phaseLengthSeconds: 1500,
        elapsedSeconds: 200,
      );
      expect(schedule.inProgressSessionSeconds(state), 200);
    });

    test('work以外は常に0', () {
      final run = _run(startPhaseIndex: 1, carriedInSeconds: 0);
      final schedule = PomodoroSchedule(run);
      final state = PomodoroPhaseState(
        phaseIndex: 1,
        type: PomodoroPhaseType.shortBreak,
        setNumber: 1,
        phaseLengthSeconds: 300,
        elapsedSeconds: 100,
      );
      expect(schedule.inProgressSessionSeconds(state), 0);
    });

    test('経過秒がcarriedInSeconds未満でも負値にならない（下限0）', () {
      final run = _run(startPhaseIndex: 0, carriedInSeconds: 300);
      final schedule = PomodoroSchedule(run);
      final state = PomodoroPhaseState(
        phaseIndex: 0,
        type: PomodoroPhaseType.work,
        setNumber: 1,
        phaseLengthSeconds: 1500,
        elapsedSeconds: 100,
      );
      expect(schedule.inProgressSessionSeconds(state), 0);
    });
  });

  group('creditForRange（完走扱いにする範囲の差分計算）', () {
    test('開始フェーズが範囲内: carriedInCreditedMinutes/carriedInSecondsを控除する', () {
      final run = _run(
        startPhaseIndex: 0,
        startPhaseLengthSecondsOverride: 1500,
        carriedInSeconds: 300,
        carriedInCreditedMinutes: 3,
      );
      final schedule = PomodoroSchedule(run);
      final result = schedule.creditForRange(0, 1);
      expect(result.completedWorkPhases, 1);
      expect(result.creditedMinutes, 25 - 3);
      expect(result.workSeconds, 1500 - 300);
    });

    test('控除がフェーズ分を超えるなら0にクランプする', () {
      final run = _run(
        startPhaseIndex: 0,
        startPhaseLengthSecondsOverride: 60,
        carriedInCreditedMinutes: 5,
      );
      final schedule = PomodoroSchedule(run);
      final result = schedule.creditForRange(0, 1);
      expect(result.creditedMinutes, 0);
    });

    test('複数フェーズ（開始フェーズ＋通常フェーズ）を合算する', () {
      final run = _run(
        startPhaseIndex: 0,
        startPhaseLengthSecondsOverride: 1500,
        carriedInSeconds: 300,
        carriedInCreditedMinutes: 3,
      );
      final schedule = PomodoroSchedule(run);
      // 0=work(開始, 控除あり) 1=short(対象外) 2=work(通常)
      final result = schedule.creditForRange(0, 3);
      expect(result.completedWorkPhases, 2);
      expect(result.creditedMinutes, (25 - 3) + 25);
      expect(result.workSeconds, (1500 - 300) + 1500);
    });

    test('スキップは使わない前提: 範囲が空なら全て0', () {
      final run = _run();
      final schedule = PomodoroSchedule(run);
      final result = schedule.creditForRange(0, 0);
      expect(result.completedWorkPhases, 0);
      expect(result.creditedMinutes, 0);
      expect(result.workSeconds, 0);
    });
  });

  group('壊れたデータへの防御（2台同時利用で相手端末が不正データを書いた場合）', () {
    test('setCount=0 でもゼロ除算せず例外にならない（1セット扱いに丸める）', () {
      final run = _run(setCount: 0);
      final schedule = PomodoroSchedule(run);
      expect(() => schedule.phaseTypeAt(0), returnsNormally);
      expect(() => schedule.setNumberAt(0), returnsNormally);
      expect(() => schedule.currentPhase(t0), returnsNormally);
      // setCount<=0 は1セット扱い（周期2）になる。
      expect(schedule.phaseTypeAt(0), PomodoroPhaseType.work);
      expect(schedule.phaseTypeAt(1), PomodoroPhaseType.longBreak);
      expect(schedule.phaseTypeAt(2), PomodoroPhaseType.work);
    });

    test('setCount が負でもゼロ除算せず例外にならない', () {
      final run = _run(setCount: -1);
      final schedule = PomodoroSchedule(run);
      expect(() => schedule.currentPhase(t0), returnsNormally);
    });

    test('workMinutes=0 でも currentPhase が無限ループせず有限時間で返る', () {
      final run = _run(
        workMinutes: 0,
        shortBreakMinutes: 0,
        longBreakMinutes: 0,
        phaseIndex: 0,
        phaseStartedAtUtc: t0,
      );
      final schedule = PomodoroSchedule(run);
      // 実時間が少し進んだだけでも length=0 だと従来は無限ループしていた。
      // 最低1秒に丸められるため、有限のフェーズ数だけ進んで正常に返る。
      final state = schedule.currentPhase(t0.add(const Duration(seconds: 5)));
      expect(state.phaseLengthSeconds, greaterThanOrEqualTo(1));
    });

    test('startPhaseLengthSecondsOverride=0 でも無限ループせず有限時間で返る', () {
      final run = _run(
        phaseIndex: 0,
        phaseStartedAtUtc: t0,
        startPhaseIndex: 0,
        startPhaseLengthSecondsOverride: 0,
      );
      final schedule = PomodoroSchedule(run);
      final state = schedule.currentPhase(t0.add(const Duration(seconds: 1)));
      expect(state.phaseLengthSeconds, greaterThanOrEqualTo(1));
    });

    test('正常データ（setCount>=1・分×60）では従来通りの挙動を保つ', () {
      // 既存の「K=4」ケースと同値であることを再確認し、ガード追加による
      // 正常系への影響が無いことを担保する。
      final run = _run(setCount: 4);
      final schedule = PomodoroSchedule(run);
      expect(schedule.phaseLengthSecondsAt(0), 25 * 60);
      expect(schedule.phaseLengthSecondsAt(7), 15 * 60);
    });
  });
}
