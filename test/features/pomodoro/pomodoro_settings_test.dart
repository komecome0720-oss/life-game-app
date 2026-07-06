import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';

void main() {
  group('PomodoroSettings.fromMap', () {
    test('null データは既定値を返す', () {
      final settings = PomodoroSettings.fromMap(null);
      expect(settings.workMinutes, PomodoroSettings.defaultWorkMinutes);
      expect(settings.shortBreakMinutes,
          PomodoroSettings.defaultShortBreakMinutes);
      expect(settings.setCount, PomodoroSettings.defaultSetCount);
      expect(
          settings.longBreakMinutes, PomodoroSettings.defaultLongBreakMinutes);
      expect(settings.bgmWork, PomodoroSettings.defaultBgmWork);
      expect(settings.bgmShortBreak, PomodoroSettings.defaultBgmShortBreak);
      expect(settings.bgmLongBreak, PomodoroSettings.defaultBgmLongBreak);
      expect(settings.soundWorkStart, PomodoroSettings.defaultSoundWorkStart);
      expect(settings.soundShortBreakStart,
          PomodoroSettings.defaultSoundShortBreakStart);
      expect(settings.soundLongBreakStart,
          PomodoroSettings.defaultSoundLongBreakStart);
    });

    test('toMap/fromMap の往復', () {
      const settings = PomodoroSettings(
        workMinutes: 50,
        shortBreakMinutes: 10,
        setCount: 2,
        longBreakMinutes: 30,
        bgmWork: PomodoroBgm.fire,
        bgmShortBreak: PomodoroBgm.birds,
        bgmLongBreak: PomodoroBgm.waves,
        soundWorkStart: PomodoroChime.bell,
        soundShortBreakStart: PomodoroChime.trumpet,
        soundLongBreakStart: PomodoroChime.drum,
      );
      final map = settings.toMap();
      final restored = PomodoroSettings.fromMap(map);

      expect(restored.workMinutes, 50);
      expect(restored.shortBreakMinutes, 10);
      expect(restored.setCount, 2);
      expect(restored.longBreakMinutes, 30);
      expect(restored.bgmWork, PomodoroBgm.fire);
      expect(restored.bgmShortBreak, PomodoroBgm.birds);
      expect(restored.bgmLongBreak, PomodoroBgm.waves);
      expect(restored.soundWorkStart, PomodoroChime.bell);
      expect(restored.soundShortBreakStart, PomodoroChime.trumpet);
      expect(restored.soundLongBreakStart, PomodoroChime.drum);
    });

    test('0以下の数値は既定値へフォールバックする', () {
      final settings = PomodoroSettings.fromMap({
        'workMinutes': 0,
        'shortBreakMinutes': -5,
        'setCount': 0,
        'longBreakMinutes': -1,
      });
      expect(settings.workMinutes, PomodoroSettings.defaultWorkMinutes);
      expect(settings.shortBreakMinutes,
          PomodoroSettings.defaultShortBreakMinutes);
      expect(settings.setCount, PomodoroSettings.defaultSetCount);
      expect(
          settings.longBreakMinutes, PomodoroSettings.defaultLongBreakMinutes);
    });

    test('未知の文字列は既定値へフォールバックする', () {
      final settings = PomodoroSettings.fromMap({
        'bgmWork': 'unknown-bgm',
        'soundWorkStart': 'unknown-sound',
      });
      expect(settings.bgmWork, PomodoroSettings.defaultBgmWork);
      expect(settings.soundWorkStart, PomodoroSettings.defaultSoundWorkStart);
    });
  });

  group('PomodoroBgm / PomodoroChime .fromId', () {
    test('既知のIDは対応する値を返す', () {
      expect(PomodoroBgm.fromId('river', PomodoroBgm.waves), PomodoroBgm.river);
      expect(PomodoroChime.fromId('bell', PomodoroChime.drum),
          PomodoroChime.bell);
    });

    test('null/未知のIDはfallbackを返す', () {
      expect(PomodoroBgm.fromId(null, PomodoroBgm.fire), PomodoroBgm.fire);
      expect(PomodoroBgm.fromId('nope', PomodoroBgm.fire), PomodoroBgm.fire);
    });
  });
}
