import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/features/todo/widgets/todo_task_detail_sheet.dart';
import 'package:task_manager/models/calendar_task.dart';

/// ToDo 1件を表示するカード。長押しでドラッグ、タップで詳細シート。
class TodoTaskCard extends ConsumerWidget {
  const TodoTaskCard({super.key, required this.task});

  final CalendarTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final cardContent = Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showTodoTaskDetailSheet(context: context, task: task),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            task.title,
            style: text.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );

    // 実際のカード幅を feedback にも反映させるために LayoutBuilder で包む
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 180.0;
        return LongPressDraggable<CalendarTask>(
          data: task,
          delay: const Duration(milliseconds: 300),
          dragAnchorStrategy: childDragAnchorStrategy,
          onDragStarted: () =>
              ref.read(draggingTodoProvider.notifier).setDragging(task),
          onDragEnd: (_) =>
              ref.read(draggingTodoProvider.notifier).setDragging(null),
          onDraggableCanceled: (_, _) =>
              ref.read(draggingTodoProvider.notifier).setDragging(null),
          onDragCompleted: () =>
              ref.read(draggingTodoProvider.notifier).setDragging(null),
          feedback: Transform.scale(
            scale: 1.03,
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: width,
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  color: scheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      task.title,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: cardContent),
          child: cardContent,
        );
      },
    );
  }
}
