import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/features/todo/widgets/todo_task_card.dart';
import 'package:task_manager/models/calendar_task.dart';

/// 4象限のうち1つを表示する。自分以外の象限からドラッグされてきた
/// CalendarTask を受け入れて、象限を更新する。
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
      onWillAcceptWithDetails: (d) {
        final t = d.data;
        if (!t.isTodo) return false;
        final current = QuadrantX.from(
          urgency: t.urgency,
          importance: t.importance,
        );
        // 同じ象限へのドロップは不要（no-op 扱い）
        return current != quadrant;
      },
      onAcceptWithDetails: (d) {
        ref.read(todoMatrixViewModelProvider).moveToQuadrant(d.data, quadrant);
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
                        itemBuilder: (_, i) => TodoTaskCard(task: tasks[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
