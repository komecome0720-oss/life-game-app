import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_day.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';

void main() {
  final t0 = DateTime.utc(2026, 7, 6, 10, 0, 0);
  const settings = PomodoroSettings(
    workMinutes: 25,
    shortBreakMinutes: 5,
    setCount: 4,
    longBreakMinutes: 15,
    bgmWork: PomodoroBgm.waves,
    bgmShortBreak: PomodoroBgm.river,
    bgmLongBreak: PomodoroBgm.birds,
    soundWorkStart: PomodoroChime.drum,
    soundShortBreakStart: PomodoroChime.bell,
    soundLongBreakStart: PomodoroChime.trumpet,
  );

  group('resolveStart: まっさら', () {
    test('doc が無い日は work の先頭から開始する', () {
      final day = PomodoroDay.empty(t0);
      final result = day.resolveStart(settings: settings, nowUtc: t0);
      expect(result.startPhaseIndex, 0);
      expect(result.startPhaseLengthSecondsOverride, isNull);
      expect(result.carriedInSeconds, 0);
      expect(result.carriedInCreditedMinutes, 0);
      expect(result.dayAfter.cycleCompletedSets, 0);
      expect(result.dayAfter.carryWork, isNull);
      expect(result.dayAfter.pendingBreak, isNull);
      expect(result.startPhaseIndex, greaterThanOrEqualTo(0));
    });
  });

  group('resolveStart: carryWork（やりかけ作業フェーズの再開）', () {
    test('サイクル内位置から再開し、経過秒・クレジット済み分を引き継ぐ', () {
      final day = PomodoroDay(
        completedSetsToday: 5,
        cycleCompletedSets: 2,
        carryWork: const PomodoroCarryWork(
          elapsedSeconds: 300,
          phaseLengthSeconds: 1500,
          creditedMinutes: 3,
        ),
        updatedAtUtc: t0,
      );
      final result = day.resolveStart(settings: settings, nowUtc: t0);
      expect(result.startPhaseIndex, 4); // pos=2 -> 2*2
      expect(result.startPhaseLengthSecondsOverride, 1500);
      expect(result.carriedInSeconds, 300);
      expect(result.carriedInCreditedMinutes, 3);
      expect(result.dayAfter.cycleCompletedSets, 2);
      expect(result.dayAfter.carryWork, isNull); // 消化済みとしてクリア
      expect(result.startPhaseIndex, greaterThanOrEqualTo(0));
    });
  });

  group('resolveStart: pendingBreak（未消化の休憩）', () {
    test('short 休憩が途中（cycleCompletedSets>=1）: 消化中の休憩から再開', () {
      final day = PomodoroDay(
        completedSetsToday: 5,
        cycleCompletedSets: 2,
        pendingBreak: PomodoroPendingBreak(
          isLong: false,
          remainingSeconds: 200,
          sinceUtc: t0,
        ),
        updatedAtUtc: t0,
      );
      final now = t0.add(const Duration(seconds: 30));
      final result = day.resolveStart(settings: settings, nowUtc: now);
      expect(result.startPhaseIndex, 3); // 2*2-1
      expect(result.startPhaseLengthSecondsOverride, 170);
      expect(result.carriedInSeconds, 0);
      expect(result.carriedInCreditedMinutes, 0);
      expect(result.dayAfter.pendingBreak, isNull);
      expect(result.dayAfter.cycleCompletedSets, 2); // 未リセット
      expect(result.startPhaseIndex, greaterThanOrEqualTo(0));
    });

    test('long 休憩が途中: 長休憩スロットから残秒で再開', () {
      final day = PomodoroDay(
        completedSetsToday: 4,
        cycleCompletedSets: 4,
        pendingBreak: PomodoroPendingBreak(
          isLong: true,
          remainingSeconds: 300,
          sinceUtc: t0,
        ),
        updatedAtUtc: t0,
      );
      final now = t0.add(const Duration(seconds: 60));
      final result = day.resolveStart(settings: settings, nowUtc: now);
      expect(result.startPhaseIndex, 7); // 2*4-1
      expect(result.startPhaseLengthSecondsOverride, 240);
      expect(result.startPhaseIndex, greaterThanOrEqualTo(0));
    });

    test('short 休憩が消化済み（remaining<=0）: cycleCompletedSetsは変わらず作業から再開', () {
      final day = PomodoroDay(
        completedSetsToday: 5,
        cycleCompletedSets: 2,
        pendingBreak: PomodoroPendingBreak(
          isLong: false,
          remainingSeconds: 100,
          sinceUtc: t0,
        ),
        updatedAtUtc: t0,
      );
      final now = t0.add(const Duration(seconds: 200));
      final result = day.resolveStart(settings: settings, nowUtc: now);
      expect(result.startPhaseIndex, 4); // pos=2 -> 2*2
      expect(result.startPhaseLengthSecondsOverride, isNull);
      expect(result.dayAfter.cycleCompletedSets, 2);
      expect(result.dayAfter.pendingBreak, isNull);
      expect(result.startPhaseIndex, greaterThanOrEqualTo(0));
    });

    test('long 休憩が消化済み: cycleCompletedSetsが0にリセットされ先頭のworkから再開', () {
      final day = PomodoroDay(
        completedSetsToday: 4,
        cycleCompletedSets: 4,
        pendingBreak: PomodoroPendingBreak(
          isLong: true,
          remainingSeconds: 100,
          sinceUtc: t0,
        ),
        updatedAtUtc: t0,
      );
      final now = t0.add(const Duration(seconds: 200));
      final result = day.resolveStart(settings: settings, nowUtc: now);
      expect(result.startPhaseIndex, 0);
      expect(result.startPhaseLengthSecondsOverride, isNull);
      expect(result.dayAfter.cycleCompletedSets, 0);
      expect(result.startPhaseIndex, greaterThanOrEqualTo(0));
    });

    test('short 休憩かつ cycleCompletedSets==0（退化ケース）: 破棄してまっさら扱い', () {
      final day = PomodoroDay(
        completedSetsToday: 0,
        cycleCompletedSets: 0,
        pendingBreak: PomodoroPendingBreak(
          isLong: false,
          remainingSeconds: 100,
          sinceUtc: t0,
        ),
        updatedAtUtc: t0,
      );
      final now = t0.add(const Duration(seconds: 10));
      final result = day.resolveStart(settings: settings, nowUtc: now);
      expect(result.startPhaseIndex, 0);
      expect(result.startPhaseLengthSecondsOverride, isNull);
      expect(result.carriedInSeconds, 0);
      expect(result.dayAfter.pendingBreak, isNull);
      expect(result.dayAfter.cycleCompletedSets, 0);
      expect(result.startPhaseIndex, greaterThanOrEqualTo(0));
    });
  });

  group('resolveStart: setCount 縮小クランプ', () {
    test('carryWork/pendingBreak 無し: サイクル内完走数が新setCount以上ならクランプする', () {
      final day = PomodoroDay(
        completedSetsToday: 3,
        cycleCompletedSets: 3,
        updatedAtUtc: t0,
      );
      const shrunk = PomodoroSettings(
        workMinutes: 25,
        shortBreakMinutes: 5,
        setCount: 2,
        longBreakMinutes: 15,
        bgmWork: PomodoroBgm.waves,
        bgmShortBreak: PomodoroBgm.river,
        bgmLongBreak: PomodoroBgm.birds,
        soundWorkStart: PomodoroChime.drum,
        soundShortBreakStart: PomodoroChime.bell,
        soundLongBreakStart: PomodoroChime.trumpet,
      );
      final result = day.resolveStart(settings: shrunk, nowUtc: t0);
      expect(result.startPhaseIndex, 2); // pos=min(3,1)=1 -> 2*1
      expect(result.startPhaseIndex, greaterThanOrEqualTo(0));
    });

    test('short 休憩途中で cycleCompletedSets が新setCountを超えていたら長休憩スロットへ振替', () {
      final day = PomodoroDay(
        completedSetsToday: 3,
        cycleCompletedSets: 3,
        pendingBreak: PomodoroPendingBreak(
          isLong: false,
          remainingSeconds: 50,
          sinceUtc: t0,
        ),
        updatedAtUtc: t0,
      );
      const shrunk = PomodoroSettings(
        workMinutes: 25,
        shortBreakMinutes: 5,
        setCount: 2,
        longBreakMinutes: 15,
        bgmWork: PomodoroBgm.waves,
        bgmShortBreak: PomodoroBgm.river,
        bgmLongBreak: PomodoroBgm.birds,
        soundWorkStart: PomodoroChime.drum,
        soundShortBreakStart: PomodoroChime.bell,
        soundLongBreakStart: PomodoroChime.trumpet,
      );
      final now = t0.add(const Duration(seconds: 10));
      final result = day.resolveStart(settings: shrunk, nowUtc: now);
      expect(result.startPhaseIndex, 3); // 長休憩スロット 2*2-1
      expect(result.startPhaseLengthSecondsOverride, 40);
      expect(result.startPhaseIndex, greaterThanOrEqualTo(0));
    });
  });

  group('fromMap/toMap 往復・欠損耐性', () {
    test('data が null なら PomodoroDay.fromMap は null を返す', () {
      expect(PomodoroDay.fromMap(null), isNull);
    });

    test('carryWork/pendingBreak 込みで往復する', () {
      final day = PomodoroDay(
        completedSetsToday: 3,
        cycleCompletedSets: 1,
        carryWork: const PomodoroCarryWork(
          elapsedSeconds: 100,
          phaseLengthSeconds: 1500,
          creditedMinutes: 2,
        ),
        updatedAtUtc: t0,
      );
      final restored = PomodoroDay.fromMap(day.toMap());
      expect(restored, isNotNull);
      expect(restored!.completedSetsToday, 3);
      expect(restored.cycleCompletedSets, 1);
      expect(restored.carryWork!.elapsedSeconds, 100);
      expect(restored.carryWork!.phaseLengthSeconds, 1500);
      expect(restored.carryWork!.creditedMinutes, 2);
      expect(restored.pendingBreak, isNull);

      final dayWithBreak = PomodoroDay(
        completedSetsToday: 4,
        cycleCompletedSets: 4,
        pendingBreak: PomodoroPendingBreak(
          isLong: true,
          remainingSeconds: 300,
          sinceUtc: t0,
        ),
        updatedAtUtc: t0,
      );
      final restoredBreak = PomodoroDay.fromMap(dayWithBreak.toMap());
      expect(restoredBreak!.pendingBreak!.isLong, isTrue);
      expect(restoredBreak.pendingBreak!.remainingSeconds, 300);
      expect(
        restoredBreak.pendingBreak!.sinceUtc.isAtSameMomentAs(t0),
        isTrue,
      );
      expect(restoredBreak.carryWork, isNull);
    });

    test('欠損したフィールドは0/nullへフォールバックする', () {
      final restored = PomodoroDay.fromMap(const {});
      expect(restored, isNotNull);
      expect(restored!.completedSetsToday, 0);
      expect(restored.cycleCompletedSets, 0);
      expect(restored.carryWork, isNull);
      expect(restored.pendingBreak, isNull);
    });
  });
}
