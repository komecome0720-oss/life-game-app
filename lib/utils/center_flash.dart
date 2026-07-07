import 'dart:async';

import 'package:flutter/material.dart';

/// 画面中央に一瞬だけメッセージを表示してフェードアウトする装飾演出。
///
/// タイマー開始時の「スタート！」のようなモチベーション演出用。
/// - ルート Overlay に載せて画面中央へ表示する。
/// - 登場（scale + fade in）→ 保持 → フェードアウトして自動で消える。
/// - [IgnorePointer] で包むためタップは常に透過する（操作を一切ブロックしない）。
///
/// 注意（UI共通ルール）：これは情報を伝える「非モーダル通知」ではなく、
/// タップをブロックしない装飾演出なので、`messageVisibleNotifier` /
/// `MessageGuard` / `showAppSnackBar` の経路は通さない。
void showCenterFlash(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: _FlashBubble(
            message: message,
            onDone: () {
              if (entry.mounted) entry.remove();
            },
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
}

/// 指定したウィジェット（[anchorKey]）のすぐ下（右端揃え）に、一瞬だけ小さめの
/// メッセージを表示してフェードアウトする装飾演出。ボタン操作に対する軽い
/// フィードバック用（例：無効な操作をタップした際の理由表示）。
///
/// [showCenterFlash] 同様、タップを一切ブロックしない演出のため
/// `messageVisibleNotifier` / `MessageGuard` / `showAppSnackBar` の経路は通さない。
void showAnchoredFlash(
  BuildContext context,
  String message, {
  required GlobalKey anchorKey,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final renderBox = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (renderBox == null || !renderBox.attached) return;
  final anchorTopLeft = renderBox.localToGlobal(Offset.zero);
  final anchorSize = renderBox.size;
  final screenWidth = MediaQuery.of(context).size.width;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      top: anchorTopLeft.dy + anchorSize.height + 4,
      right: screenWidth - (anchorTopLeft.dx + anchorSize.width),
      child: IgnorePointer(
        child: _FlashBubble(
          message: message,
          compact: true,
          onDone: () {
            if (entry.mounted) entry.remove();
          },
        ),
      ),
    ),
  );
  overlay.insert(entry);
}

class _FlashBubble extends StatefulWidget {
  const _FlashBubble({
    required this.message,
    required this.onDone,
    this.compact = false,
  });

  final String message;
  final VoidCallback onDone;

  /// true の場合、ボタン近傍のツールチップ用に一回り小さく表示する。
  final bool compact;

  @override
  State<_FlashBubble> createState() => _FlashBubbleState();
}

class _FlashBubbleState extends State<_FlashBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  Timer? _removeTimer;

  // 登場150ms → 保持500ms → フェードアウト250ms（合計約900ms）。
  static const _appear = Duration(milliseconds: 150);
  static const _hold = Duration(milliseconds: 500);
  static const _fadeOut = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    final total = _appear + _hold + _fadeOut;
    _ctrl = AnimationController(vsync: this, duration: total);

    final appearEnd = _appear.inMilliseconds / total.inMilliseconds;
    final fadeOutStart =
        (_appear + _hold).inMilliseconds / total.inMilliseconds;

    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0),
        weight: appearEnd,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: fadeOutStart - appearEnd,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0),
        weight: 1.0 - fadeOutStart,
      ),
    ]).animate(_ctrl);

    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Interval(0.0, appearEnd, curve: Curves.easeOutBack),
      ),
    );

    _ctrl.forward();
    _removeTimer = Timer(total, widget.onDone);
  }

  @override
  void dispose() {
    _removeTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        alignment: widget.compact ? Alignment.topRight : Alignment.center,
        child: Container(
          padding: widget.compact
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
              : const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(widget.compact ? 12 : 20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: widget.compact ? 8 : 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            widget.message,
            style:
                (widget.compact ? text.bodyMedium : text.displaySmall)?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
