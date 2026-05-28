import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/models/calendar_task.dart';

/// 長押しドラッグ中に画面上部から出現するドロップターゲット。
/// 指をここに重ねると、親（MainShell）にタブ切替を依頼する。
class CalendarDropBar extends ConsumerWidget {
  const CalendarDropBar({super.key, required this.onSwitchToCalendar});

  /// 指がバー上にホバーしたときに呼ばれる（ホームタブへ切替）。
  final VoidCallback onSwitchToCalendar;

  static const double barHeight = 38;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dragging = ref.watch(draggingTodoProvider) != null;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return IgnorePointer(
      ignoring: !dragging,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: dragging ? Offset.zero : const Offset(0, -1.2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: dragging ? 1.0 : 0.0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: DragTarget<CalendarTask>(
              onWillAcceptWithDetails: (d) => d.data.isTodo,
              onMove: (_) => onSwitchToCalendar(),
              onAcceptWithDetails: (_) {
                // この時点で既にホームタブへ遷移済み。実際のスロット配置は
                // WeekSchedulePanel 側の DragTarget が処理する。
              },
              builder: (context, candidate, rejected) {
                final isHover = candidate.isNotEmpty;
                return Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: isHover
                        ? scheme.primary.withValues(alpha: 0.18)
                        : scheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          isHover ? scheme.primary : scheme.primary.withValues(alpha: 0.5),
                      width: isHover ? 2 : 1.2,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month,
                          color: scheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ここに重ねてカレンダーに追加',
                          style: text.labelMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.add,
                          color: scheme.primary.withValues(alpha: 0.8),
                          size: 18),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
