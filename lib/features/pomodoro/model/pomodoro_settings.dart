import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// ポモドーロで再生する BGM の種類。
enum PomodoroBgm {
  waves('waves', 'assets/audio/bgm_waves.mp3', '波の音'),
  river('river', 'assets/audio/bgm_river.m4a', '川のせせらぎ'),
  fire('fire', 'assets/audio/bgm_fire.m4a', '焚き火'),
  birds('birds', 'assets/audio/bgm_birds.m4a', '鳥のさえずり');

  const PomodoroBgm(this.id, this.assetPath, this.label);

  final String id;
  final String assetPath;
  final String label;

  static PomodoroBgm fromId(String? id, PomodoroBgm fallback) {
    for (final v in values) {
      if (v.id == id) return v;
    }
    return fallback;
  }
}

/// フェーズ切り替え時に鳴らすチャイム（効果音）の種類。
enum PomodoroChime {
  drum('drum', 'assets/audio/sfx_drum.wav', '太鼓'),
  bell('bell', 'assets/audio/sfx_bell.wav', '鈴'),
  trumpet('trumpet', 'assets/audio/sfx_trumpet.mp3', 'ラッパ');

  const PomodoroChime(this.id, this.assetPath, this.label);

  final String id;
  final String assetPath;
  final String label;

  static PomodoroChime fromId(String? id, PomodoroChime fallback) {
    for (final v in values) {
      if (v.id == id) return v;
    }
    return fallback;
  }
}

/// ポモドーロ設定（`users/{uid}/settings/pomodoro`）。
///
/// ユーザー全体で共通の1ドキュメント。不正値（0以下・未知の文字列）は
/// [fromMap] で既定値へフォールバックする（既存 doc の部分欠落にも耐える）。
@immutable
class PomodoroSettings {
  const PomodoroSettings({
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
  });

  static const defaultWorkMinutes = 25;
  static const defaultShortBreakMinutes = 5;
  static const defaultSetCount = 4;
  static const defaultLongBreakMinutes = 15;
  static const defaultBgmWork = PomodoroBgm.waves;
  static const defaultBgmShortBreak = PomodoroBgm.river;
  static const defaultBgmLongBreak = PomodoroBgm.birds;
  static const defaultSoundWorkStart = PomodoroChime.drum;
  static const defaultSoundShortBreakStart = PomodoroChime.bell;
  static const defaultSoundLongBreakStart = PomodoroChime.trumpet;

  static const defaults = PomodoroSettings(
    workMinutes: defaultWorkMinutes,
    shortBreakMinutes: defaultShortBreakMinutes,
    setCount: defaultSetCount,
    longBreakMinutes: defaultLongBreakMinutes,
    bgmWork: defaultBgmWork,
    bgmShortBreak: defaultBgmShortBreak,
    bgmLongBreak: defaultBgmLongBreak,
    soundWorkStart: defaultSoundWorkStart,
    soundShortBreakStart: defaultSoundShortBreakStart,
    soundLongBreakStart: defaultSoundLongBreakStart,
  );

  final int workMinutes;
  final int shortBreakMinutes;
  final int setCount;
  final int longBreakMinutes;
  final PomodoroBgm bgmWork;
  final PomodoroBgm bgmShortBreak;
  final PomodoroBgm bgmLongBreak;
  final PomodoroChime soundWorkStart;
  final PomodoroChime soundShortBreakStart;
  final PomodoroChime soundLongBreakStart;

  PomodoroSettings copyWith({
    int? workMinutes,
    int? shortBreakMinutes,
    int? setCount,
    int? longBreakMinutes,
    PomodoroBgm? bgmWork,
    PomodoroBgm? bgmShortBreak,
    PomodoroBgm? bgmLongBreak,
    PomodoroChime? soundWorkStart,
    PomodoroChime? soundShortBreakStart,
    PomodoroChime? soundLongBreakStart,
  }) {
    return PomodoroSettings(
      workMinutes: workMinutes ?? this.workMinutes,
      shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
      setCount: setCount ?? this.setCount,
      longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
      bgmWork: bgmWork ?? this.bgmWork,
      bgmShortBreak: bgmShortBreak ?? this.bgmShortBreak,
      bgmLongBreak: bgmLongBreak ?? this.bgmLongBreak,
      soundWorkStart: soundWorkStart ?? this.soundWorkStart,
      soundShortBreakStart:
          soundShortBreakStart ?? this.soundShortBreakStart,
      soundLongBreakStart: soundLongBreakStart ?? this.soundLongBreakStart,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'workMinutes': workMinutes,
      'shortBreakMinutes': shortBreakMinutes,
      'setCount': setCount,
      'longBreakMinutes': longBreakMinutes,
      'bgmWork': bgmWork.id,
      'bgmShortBreak': bgmShortBreak.id,
      'bgmLongBreak': bgmLongBreak.id,
      'soundWorkStart': soundWorkStart.id,
      'soundShortBreakStart': soundShortBreakStart.id,
      'soundLongBreakStart': soundLongBreakStart.id,
      'updatedAtUtc': Timestamp.fromDate(DateTime.now().toUtc()),
    };
  }

  static int _positiveIntOrDefault(dynamic value, int fallback) {
    final n = (value as num?)?.toInt();
    if (n == null || n <= 0) return fallback;
    return n;
  }

  factory PomodoroSettings.fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    return PomodoroSettings(
      workMinutes:
          _positiveIntOrDefault(data['workMinutes'], defaultWorkMinutes),
      shortBreakMinutes: _positiveIntOrDefault(
          data['shortBreakMinutes'], defaultShortBreakMinutes),
      setCount: _positiveIntOrDefault(data['setCount'], defaultSetCount),
      longBreakMinutes: _positiveIntOrDefault(
          data['longBreakMinutes'], defaultLongBreakMinutes),
      bgmWork: PomodoroBgm.fromId(data['bgmWork'] as String?, defaultBgmWork),
      bgmShortBreak: PomodoroBgm.fromId(
          data['bgmShortBreak'] as String?, defaultBgmShortBreak),
      bgmLongBreak: PomodoroBgm.fromId(
          data['bgmLongBreak'] as String?, defaultBgmLongBreak),
      soundWorkStart: PomodoroChime.fromId(
          data['soundWorkStart'] as String?, defaultSoundWorkStart),
      soundShortBreakStart: PomodoroChime.fromId(
          data['soundShortBreakStart'] as String?,
          defaultSoundShortBreakStart),
      soundLongBreakStart: PomodoroChime.fromId(
          data['soundLongBreakStart'] as String?,
          defaultSoundLongBreakStart),
    );
  }
}
