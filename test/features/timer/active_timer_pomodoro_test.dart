import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/timer/model/active_timer.dart';
import 'package:task_manager/features/timer/model/pomodoro_run.dart';

ActiveTimer _baseTimer({PomodoroRun? pomodoro}) {
  return ActiveTimer(
    taskId: 'task-1',
    isTodo: false,
    taskTitle: 'サンプル',
    predictedMinutes: 60,
    startedAtUtc: null,
    accumulatedSeconds: 0,
    updatedAtUtc: DateTime.utc(2026, 7, 6, 10, 0, 0),
    pomodoro: pomodoro,
  );
}

PomodoroRun _samplePomodoroRun() {
  return PomodoroRun(
    workMinutes: 25,
    shortBreakMinutes: 5,
    setCount: 4,
    longBreakMinutes: 15,
    bgmWork: 'waves',
    bgmShortBreak: 'river',
    bgmLongBreak: 'birds',
    soundWorkStart: 'drum',
    soundShortBreakStart: 'bell',
    soundLongBreakStart: 'trumpet',
    phaseIndex: 3,
    phaseStartedAtUtc: DateTime.utc(2026, 7, 6, 10, 5, 0),
    phaseAccumulatedSeconds: 12,
    savedWorkPhases: 2,
    baseActualMinutes: 40,
  );
}

void main() {
  group('ActiveTimer.pomodoro 直列化', () {
    test('pomodoro ありの往復変換', () {
      final timer = _baseTimer(pomodoro: _samplePomodoroRun());
      final map = timer.toMap();
      expect(map['pomodoro'], isNotNull);

      final restored = ActiveTimer.fromMap(map);
      expect(restored.pomodoro, isNotNull);
      final run = restored.pomodoro!;
      expect(run.workMinutes, 25);
      expect(run.shortBreakMinutes, 5);
      expect(run.setCount, 4);
      expect(run.longBreakMinutes, 15);
      expect(run.bgmWork, 'waves');
      expect(run.bgmShortBreak, 'river');
      expect(run.bgmLongBreak, 'birds');
      expect(run.soundWorkStart, 'drum');
      expect(run.soundShortBreakStart, 'bell');
      expect(run.soundLongBreakStart, 'trumpet');
      expect(run.phaseIndex, 3);
      expect(
        run.phaseStartedAtUtc!.isAtSameMomentAs(
          DateTime.utc(2026, 7, 6, 10, 5, 0),
        ),
        isTrue,
      );
      expect(run.phaseAccumulatedSeconds, 12);
      expect(run.savedWorkPhases, 2);
      expect(run.baseActualMinutes, 40);
    });

    test('pomodoro なし（通常タイマー）は null のまま往復する', () {
      final timer = _baseTimer();
      final map = timer.toMap();
      expect(map['pomodoro'], isNull);

      final restored = ActiveTimer.fromMap(map);
      expect(restored.pomodoro, isNull);
    });

    test('既存doc（pomodoroキー自体が無い）は後方互換でnullになる', () {
      final legacyMap = {
        'taskId': 'task-1',
        'isTodo': false,
        'taskTitle': 'サンプル',
        'predictedMinutes': 60,
        'startedAtUtc': null,
        'accumulatedSeconds': 0,
        'updatedAtUtc': _baseTimer().toMap()['updatedAtUtc'],
      };
      final restored = ActiveTimer.fromMap(legacyMap);
      expect(restored.pomodoro, isNull);
    });

    test('一時停止中（phaseStartedAtUtc=null）のpomodoroも往復する', () {
      final pausedRun = _samplePomodoroRun().copyWith(
        clearPhaseStartedAt: true,
      );
      final timer = _baseTimer(pomodoro: pausedRun);
      final restored = ActiveTimer.fromMap(timer.toMap());
      expect(restored.pomodoro!.phaseStartedAtUtc, isNull);
      expect(restored.pomodoro!.isRunning, isFalse);
    });

    test('「1日通しセット」用の追加フィールドが往復する', () {
      final run = _samplePomodoroRun().copyWith(
        startPhaseIndex: 5,
        startPhaseLengthSecondsOverride: 300,
        carriedInSeconds: 90,
        carriedInCreditedMinutes: 4,
        creditedMinutes: 77,
        dateKey: '2026-07-06',
      );
      final timer = _baseTimer(pomodoro: run);
      final restored = ActiveTimer.fromMap(timer.toMap());
      final restoredRun = restored.pomodoro!;
      expect(restoredRun.startPhaseIndex, 5);
      expect(restoredRun.startPhaseLengthSecondsOverride, 300);
      expect(restoredRun.carriedInSeconds, 90);
      expect(restoredRun.carriedInCreditedMinutes, 4);
      expect(restoredRun.creditedMinutes, 77);
      expect(restoredRun.dateKey, '2026-07-06');
    });

    test('旧doc（新フィールド無し）は後方互換の既定値になり、'
        'creditedMinutesはsavedWorkPhases×workMinutesで補完される', () {
      final legacyMap = _samplePomodoroRun().toMap()
        ..remove('startPhaseIndex')
        ..remove('startPhaseLengthSecondsOverride')
        ..remove('carriedInSeconds')
        ..remove('carriedInCreditedMinutes')
        ..remove('creditedMinutes')
        ..remove('dateKey');
      final restored = PomodoroRun.fromMap(legacyMap)!;
      expect(restored.startPhaseIndex, 0);
      expect(restored.startPhaseLengthSecondsOverride, isNull);
      expect(restored.carriedInSeconds, 0);
      expect(restored.carriedInCreditedMinutes, 0);
      // savedWorkPhases=2, workMinutes=25 -> 50（旧計算 base+saved*work と同値）。
      expect(restored.creditedMinutes, 2 * 25);
      expect(restored.dateKey, '');
    });
  });
}
