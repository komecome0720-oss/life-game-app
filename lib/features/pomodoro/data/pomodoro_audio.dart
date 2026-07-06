import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';

/// ポモドーロのBGM・切り替え音（チャイム）再生を抽象化するインターフェース。
/// テストでは no-op fake に差し替える。
abstract class PomodoroAudio {
  /// フェーズ開始時に呼ぶ。[chime] が非null ならまずチャイムを再生してから
  /// [bgm] のループ再生を開始する。[chime] が null なら BGM のみ切り替える。
  Future<void> playPhase({required PomodoroBgm bgm, PomodoroChime? chime});

  /// 一時停止：BGMを止める（アプリがバックグラウンドで suspend され得る）。
  Future<void> pause();

  /// 再開：直前の BGM をループ再生で再開する。
  Future<void> resume();

  /// 完全停止：BGM・チャイムともに停止する（完了・✕時）。
  Future<void> stop();

  /// 設定画面の試聴用：指定アセットを1回だけ再生する。
  Future<void> preview(String assetPath);

  Future<void> dispose();
}

/// `just_audio` + `audio_session` によるバックグラウンド再生対応実装。
///
/// BGM用プレイヤー1つ（`LoopMode.one`）＋効果音・試聴用プレイヤー1つを持つ。
/// AVAudioSession の configure は初回再生時に1回だけ行う（`playback` カテゴリ
/// → バックグラウンド再生・サイレントスイッチ無視）。
/// 電話着信等での割り込みを listen し、割り込み終了時に BGM を自動再開する。
class JustAudioPomodoroAudio implements PomodoroAudio {
  JustAudioPomodoroAudio();

  final AudioPlayer _bgmPlayer = AudioPlayer();
  final AudioPlayer _sfxPlayer = AudioPlayer();

  bool _sessionConfigured = false;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  String? _currentBgmAsset;
  bool _pausedByUser = false;

  Future<void> _ensureSessionConfigured() async {
    if (_sessionConfigured) return;
    _sessionConfigured = true;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _interruptionSub = session.interruptionEventStream.listen((event) {
      if (event.begin) return;
      // 割り込み終了：ユーザー自身が一時停止していない限り BGM を再開する。
      if (!_pausedByUser && event.type != AudioInterruptionType.unknown) {
        unawaited(_resumeBgm());
      }
    });
  }

  Future<void> _resumeBgm() async {
    if (_currentBgmAsset == null) return;
    unawaited(_bgmPlayer.play());
  }

  @override
  Future<void> playPhase({
    required PomodoroBgm bgm,
    PomodoroChime? chime,
  }) async {
    await _ensureSessionConfigured();
    _pausedByUser = false;
    if (chime != null) {
      await _sfxPlayer.setAsset(chime.assetPath);
      unawaited(_sfxPlayer.play());
    }
    if (_currentBgmAsset != bgm.assetPath) {
      _currentBgmAsset = bgm.assetPath;
      await _bgmPlayer.setAsset(bgm.assetPath);
      await _bgmPlayer.setLoopMode(LoopMode.one);
    }
    // just_audio の play() はループ再生では永遠に完了しないため await しない
    // （await すると呼び出し元のロック画面 push 等がハングする）。
    unawaited(_bgmPlayer.play());
  }

  @override
  Future<void> pause() async {
    _pausedByUser = true;
    await _bgmPlayer.pause();
  }

  @override
  Future<void> resume() async {
    await _ensureSessionConfigured();
    _pausedByUser = false;
    unawaited(_bgmPlayer.play());
  }

  @override
  Future<void> stop() async {
    _pausedByUser = true;
    await _bgmPlayer.stop();
    await _sfxPlayer.stop();
  }

  @override
  Future<void> preview(String assetPath) async {
    await _ensureSessionConfigured();
    await _sfxPlayer.setAsset(assetPath);
    // 試聴もクリップの再生完了まで待たない（BGM素材は数分あり得るため）。
    unawaited(_sfxPlayer.play());
  }

  @override
  Future<void> dispose() async {
    await _interruptionSub?.cancel();
    await _bgmPlayer.dispose();
    await _sfxPlayer.dispose();
  }
}
