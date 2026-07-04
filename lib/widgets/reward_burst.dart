import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Lottie 素材があれば1回再生し、無ければ child をスケールインさせる演出ラッパー。
/// 演出は通知ではないため messageVisibleNotifier は操作しない。
/// タップを奪わないよう、利用側で必ず IgnorePointer 内に置くこと。
class RewardBurst extends StatelessWidget {
  const RewardBurst(
      {super.key, required this.assetName, required this.fallback, this.size = 160});

  final String assetName;
  final Widget fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      'assets/lottie/$assetName.json',
      width: size,
      height: size,
      repeat: false,
      errorBuilder: (context, error, stackTrace) => _Fallback(child: fallback),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, value, child) => Transform.scale(scale: value, child: child),
      child: child,
    );
  }
}
