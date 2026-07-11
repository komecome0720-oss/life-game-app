import 'package:flutter/material.dart';

const double _kActionButtonSize = 56;
const double _kVerticalGap = 16;

/// [QuickActionFab] の長押しで表示される1つのクイックアクション。
///
/// 複数要素を渡すと FAB の真上に縦積みで表示される
/// （リストの先頭＝FAB に最も近い位置）。[label] を指定すると
/// ボタンの左に小さなラベルが表示される（null なら非表示）。
class QuickAction {
  const QuickAction({
    required this.icon,
    this.tooltip,
    this.label,
    required this.onTrigger,
  });

  final IconData icon;
  final String? tooltip;
  final String? label;
  final VoidCallback onTrigger;
}

/// 長押しクイックアクション付きの汎用 FAB。
///
/// - 短タップ：[onTap] を呼ぶ（従来の FAB と同じ挙動）。
/// - 長押し：FAB の真上に [actions] の数だけアクションボタンとスクリムを表示。
///   指を離した位置がいずれかのアクションボタン上なら該当アクションを発動、
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
  final ValueNotifier<int> _hoveredIndex = ValueNotifier<int>(-1);
  List<Rect> _actionRects = const [];

  @override
  void dispose() {
    _removeOverlay();
    _hoveredIndex.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _actionRects = const [];
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (widget.actions.isEmpty) return;
    final renderBox = _fabKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;
    final fabTopLeft = renderBox.localToGlobal(Offset.zero);
    final fabSize = renderBox.size;

    final actionLeft =
        fabTopLeft.dx + (fabSize.width - _kActionButtonSize) / 2;
    _actionRects = [
      for (var i = 0; i < widget.actions.length; i++)
        Rect.fromLTWH(
          actionLeft,
          fabTopLeft.dy -
              (_kVerticalGap + _kActionButtonSize) * (i + 1),
          _kActionButtonSize,
          _kActionButtonSize,
        ),
    ];
    _hoveredIndex.value = -1;

    _overlayEntry = OverlayEntry(
      builder: (context) => _QuickActionOverlay(
        actionRects: _actionRects,
        actions: widget.actions,
        hoveredIndex: _hoveredIndex,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final rects = _actionRects;
    if (rects.isEmpty) return;
    var index = -1;
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].contains(details.globalPosition)) {
        index = i;
        break;
      }
    }
    _hoveredIndex.value = index;
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final index = _hoveredIndex.value;
    final action =
        (index >= 0 && index < widget.actions.length) ? widget.actions[index] : null;
    _removeOverlay();
    if (action != null) {
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
    required this.actionRects,
    required this.actions,
    required this.hoveredIndex,
  });

  final List<Rect> actionRects;
  final List<QuickAction> actions;
  final ValueNotifier<int> hoveredIndex;

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
        for (var i = 0; i < actionRects.length; i++)
          Positioned(
            left: actionRects[i].left,
            top: actionRects[i].top,
            width: actionRects[i].width,
            height: actionRects[i].height,
            child: IgnorePointer(
              child: ValueListenableBuilder<int>(
                valueListenable: hoveredIndex,
                builder: (context, hovered, _) {
                  final over = hovered == i;
                  final action = actions[i];
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerRight,
                    children: [
                      if (action.label != null)
                        Positioned(
                          right: _kActionButtonSize + 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              action.label!,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: colorScheme.onSurface),
                            ),
                          ),
                        ),
                      AnimatedScale(
                        scale: over ? 1.15 : 1.0,
                        duration: const Duration(milliseconds: 120),
                        child: FloatingActionButton(
                          heroTag: null,
                          tooltip: action.tooltip,
                          backgroundColor:
                              over ? colorScheme.primary : colorScheme.secondary,
                          onPressed: null,
                          child: Icon(action.icon),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
