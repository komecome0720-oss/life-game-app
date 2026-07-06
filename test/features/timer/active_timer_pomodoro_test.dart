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
  });
}
