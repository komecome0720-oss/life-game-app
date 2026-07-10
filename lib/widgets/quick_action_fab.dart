import 'package:flutter/material.dart';

/// [QuickActionFab] の長押しで表示される1つのクイックアクション。
///
/// 現状は 1 要素のみを渡す前提の最小実装（FAB の真上に1つだけ表示する）。
/// 将来複数対応する場合は、縦積みレイアウト＋各アクションごとの矩形判定への
/// 拡張ポイントとしてこのクラスをそのまま使う想定。
class QuickAction {
  const QuickAction({
    required this.icon,
    this.tooltip,
    required this.onTrigger,
  });

  final IconData icon;
  final String? tooltip;
  final VoidCallback onTrigger;
}

/// 長押しクイックアクション付きの汎用 FAB。
///
/// - 短タップ：[onTap] を呼ぶ（従来の FAB と同じ挙動）。
/// - 長押し：FAB の真上にチェックマーク等のアクションボタンとスクリムを表示。
///   指を離した位置がアクションボタン上なら該当アクションを発動、
///   それ以外の位置で離すとキャンセルする（1ジェスチャーのドラッグ＆リリース）。
class QuickActionFab extends StatefulWidget {
  const QuickActionFab({
    super.key,
    required this.heroTag,
    required this.icon,
    required this.onTap,
    required this.actions,
    this.tooltip,
  });

  final Object? heroTag;
  final IconData icon;
  final VoidCallback onTap;
  final List<QuickAction> actions;
  final String? tooltip;

  @override
  State<QuickActionFab> createState() => _QuickActionFabState();
}

class _QuickActionFabState extends State<QuickActionFab> {
  final GlobalKey _fabKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  final ValueNotifier<bool> _isOver = ValueNotifier<bool>(false);
  Rect? _actionRect;

  static const double _actionButtonSize = 56;
  static const double _verticalGap = 16;

  @override
  void dispose() {
    _removeOverlay();
    _isOver.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _actionRect = null;
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (widget.actions.isEmpty) return;
    final renderBox = _fabKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;
    final fabTopLeft = renderBox.localToGlobal(Offset.zero);
    final fabSize = renderBox.size;

    final action = widget.actions.first;
    final actionLeft =
        fabTopLeft.dx + (fabSize.width - _actionButtonSize) / 2;
    final actionTop =
        fabTopLeft.dy - _verticalGap - _actionButtonSize;
    _actionRect = Rect.fromLTWH(
      actionLeft,
      actionTop,
      _actionButtonSize,
      _actionButtonSize,
    );
    _isOver.value = false;

    _overlayEntry = OverlayEntry(
      builder: (context) => _QuickActionOverlay(
        actionRect: _actionRect!,
        action: action,
        isOver: _isOver,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final rect = _actionRect;
    if (rect == null) return;
    _isOver.value = rect.contains(details.globalPosition);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final wasOver = _isOver.value;
    final action = widget.actions.isNotEmpty ? widget.actions.first : null;
    _removeOverlay();
    if (wasOver && action != null) {
      action.onTrigger();
    }
  }

  void _onLongPressCancel() {
    _removeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _onLongPressCancel,
      child: FloatingActionButton(
        key: _fabKey,
        heroTag: widget.heroTag,
        tooltip: widget.tooltip,
        onPressed: widget.onTap,
        child: Icon(widget.icon),
      ),
    );
  }
}

class _QuickActionOverlay extends StatelessWidget {
  const _QuickActionOverlay({
    required this.actionRect,
    required this.action,
    required this.isOver,
  });

  final Rect actionRect;
  final QuickAction action;
  final ValueNotifier<bool> isOver;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Container(color: Colors.black26),
          ),
        ),
        Positioned(
          left: actionRect.left,
          top: actionRect.top,
          width: actionRect.width,
          height: actionRect.height,
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: isOver,
              builder: (context, over, _) {
                return AnimatedScale(
                  scale: over ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 120),
                  child: FloatingActionButton(
                    heroTag: null,
                    tooltip: action.tooltip,
                    backgroundColor: over
                        ? colorScheme.primary
                        : colorScheme.secondary,
                    onPressed: null,
                    child: Icon(action.icon),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
