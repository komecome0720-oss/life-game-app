import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 設定画面の「使い方をもう一度見る」がインクリメントするトリガー用カウンタ。
/// OnboardingGate がこの変化を検知してコーチマークの再生を開始する。
class OnboardingReplayNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void trigger() => state++;
}

final onboardingReplayProvider =
    NotifierProvider<OnboardingReplayNotifier, int>(OnboardingReplayNotifier.new);
