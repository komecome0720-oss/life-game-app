import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/pomodoro/data/pomodoro_audio.dart';
import 'package:task_manager/features/pomodoro/data/pomodoro_settings_repository.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';

final pomodoroSettingsRepositoryProvider =
    Provider<PomodoroSettingsRepository>((_) => PomodoroSettingsRepository());

/// ポモドーロ設定を監視する（未設定・未認証時は既定値）。
final pomodoroSettingsStreamProvider = StreamProvider<PomodoroSettings>((ref) {
  return ref.watch(pomodoroSettingsRepositoryProvider).watch();
});

/// BGM・チャイム再生を担うオーディオ実装。アプリ全体で1インスタンスを共有する。
/// テストでは no-op fake に override する。
final pomodoroAudioProvider = Provider<PomodoroAudio>((ref) {
  final audio = JustAudioPomodoroAudio();
  ref.onDispose(() {
    // ignore: discarded_futures
    audio.dispose();
  });
  return audio;
});
