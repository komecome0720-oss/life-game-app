import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/features/todo/widgets/todo_task_card.dart';
import 'package:task_manager/models/calendar_task.dart';

/// 4象限のうち1つを表示する。ドラッグされてきた CalendarTask を
/// 受け入れて、象限・並び順を更新する。
class TodoQuadrant extends ConsumerWidget {
  const TodoQuadrant({
    super.key,
    required this.quadrant,
    required this.tasks,
    required this.backgroundColor,
    required this.accentColor,
  });

  final Quadrant quadrant;
  final List<CalendarTask> tasks;
  final Color backgroundColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return DragTarget<CalendarTask>(
      // カード上でのドロップは各カードの DragTarget が内側で処理するため、
      // ここに落ちてくるのは空きエリア（余白・空象限）へのドロップ＝末尾追加。
      // ToDo 同士の並び替えに加え、完了済みでないカレンダー予定のToDo化も受け付ける。
      onWillAcceptWithDetails: (d) => d.data.isTodo || !d.data.isCompleted,
      onAcceptWithDetails: (d) {
        if (d.data.isTodo) {
          ref.read(todoMatrixViewModelProvider).reorderTask(
                dragged: d.data,
                quadrant: quadrant,
                quadrantTasks: tasks,
                insertIndex: tasks.length,
              );
        } else {
          ref.read(todoMatrixViewModelProvider).convertCalendarTaskToTodo(
                dragged: d.data,
                quadrant: quadrant,
                quadrantTasks: tasks,
              );
        }
      },
      builder: (context, candidate, rejected) {
        final isHovering = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isHovering
                ? accentColor.withValues(alpha: 0.18)
                : backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isHovering ? accentColor : scheme.outlineVariant,
              width: isHovering ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${quadrant.number}',
                      style: text.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${tasks.length}',
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Text(
                          'タスクなし',
                          style: text.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        itemCount: tasks.length,
                        itemBuilder: (_, i) => _QuadrantCardDropTarget(
                          quadrant: quadrant,
                          tasks: tasks,
                          index: i,
                          accentColor: accentColor,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// タスクカード1件分のドロップターゲット。ホバー位置の上半分/下半分で
/// 「このカードの前 / 後に挿入」を切り替え、挿入位置に線を表示する。
///
/// 自分自身のカードも accept する（Flutter の DragTarget はヒットパス上で
/// 最初に accept したターゲットのみをアクティブにし、reject すると外側の
/// ターゲットへフォールスルーする。自分自身を reject すると、
/// childWhenDragging の残像上で指を離しただけで外側＝末尾追加が誤発動する）。
/// no-op 判定は reorderTask 側（computeReorderedList）に一元化している。
class _QuadrantCardDropTarget extends ConsumerStatefulWidget {
  const _QuadrantCardDropTarget({
    required this.quadrant,
    required this.tasks,
    required this.index,
    required this.accentColor,
  });

  final Quadrant quadrant;
  final List<CalendarTask> tasks;
  final int index;
  final Color accentColor;

  @override
  ConsumerState<_QuadrantCardDropTarget> createState() =>
      _QuadrantCardDropTargetState();
}

class _QuadrantCardDropTargetState
    extends ConsumerState<_QuadrantCardDropTarget> {
  final GlobalKey _cardKey = GlobalKey();

  /// true: カードの前に挿入 / false: カードの後に挿入 / null: 未計算
  bool? _insertBefore;

  void _updateInsertBefore(Offset globalOffset) {
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(globalOffset);
    final before = local.dy < box.size.height / 2;
    if (before != _insertBefore) {
      setState(() => _insertBefore = before);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.tasks[widget.index];

    return DragTarget<CalendarTask>(
      onWillAcceptWithDetails: (d) => d.data.isTodo,
      onMove: (d) => _updateInsertBefore(d.offset),
      onLeave: (_) {
        if (_insertBefore != null) setState(() => _insertBefore = null);
      },
      onAcceptWithDetails: (d) {
        final before = _insertBefore ?? true;
        setState(() => _insertBefore = null);
        ref.read(todoMatrixViewModelProvider).reorderTask(
              dragged: d.data,
              quadrant: widget.quadrant,
              quadrantTasks: widget.tasks,
              insertIndex: before ? widget.index : widget.index + 1,
            );
      },
      builder: (context, candidate, rejected) {
        // 自分自身のカードへのホバーは常に no-op なので挿入線は出さない。
        final isSelf = candidate.any((t) => t?.id == task.id);
        final showIndicator = candidate.isNotEmpty && !isSelf;
        final indicatorLine = AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: showIndicator ? 3 : 0,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: widget.accentColor,
            borderRadius: BorderRadius.circular(2),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showIndicator && _insertBefore == true) indicatorLine,
            KeyedSubtree(key: _cardKey, child: TodoTaskCard(task: task)),
            if (showIndicator && _insertBefore == false) indicatorLine,
          ],
        );
      },
    );
  }
}
