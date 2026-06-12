import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/utils/app_messenger.dart';

/// カレンダーの表示モード。
enum CalendarViewMode { week, day }

/// PageView の外側に固定配置する共通ヘッダー。スワイプ・モード切替で位置がずれない。
class ScheduleHeaderBar extends StatelessWidget {
  const ScheduleHeaderBar({
    super.key,
    required this.viewMode,
    required this.isOnToday,
    this.onViewModeChanged,
    this.onJumpToToday,
    this.onImportFromCalendar,
    this.isImporting = false,
  });

  final CalendarViewMode viewMode;
  final bool isOnToday;
  final ValueChanged<CalendarViewMode>? onViewModeChanged;
  final VoidCallback? onJumpToToday;
  final VoidCallback? onImportFromCalendar;
  final bool isImporting;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: scheme.primary, size: 20),
          const SizedBox(width: 6),
          Text(
            'クエスト',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          SegmentedButton<CalendarViewMode>(
            segments: const [
              ButtonSegment(value: CalendarViewMode.week, label: Text('週')),
              ButtonSegment(value: CalendarViewMode.day, label: Text('日')),
            ],
            selected: {viewMode},
            onSelectionChanged: onViewModeChanged == null
                ? null
                : (set) => onViewModeChanged!(set.first),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 8, vertical: 0)),
              textStyle: WidgetStatePropertyAll(
                  TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '今日',
            onPressed: isOnToday ? null : onJumpToToday,
            icon: const Icon(Icons.today, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          if (onImportFromCalendar != null)
            isImporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.tonalIcon(
                    onPressed: onImportFromCalendar,
                    icon: const Icon(Icons.cloud_download_outlined, size: 14),
                    label: const Text('取得'),
                    style: FilledButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
        ],
      ),
    );
  }
}

/// [visibleDays]（1〜7日分、0:00 ローカル）を列として、タスクを0〜24時の時間グリッドに表示。
/// ヘッダーは [ScheduleHeaderBar] が別途親側で描画する想定。
class WeekSchedulePanel extends ConsumerStatefulWidget {
  const WeekSchedulePanel({
    super.key,
    required this.visibleDays,
    required this.tasks,
    required this.onTaskTap,
    this.onEmptyTap,
    this.onReadOnlyMoveAttempt,
    this.taskIds = const <String>{},
  }) : assert(visibleDays.length >= 1 && visibleDays.length <= 7);

  final List<DateTime> visibleDays;
  final List<CalendarTask> tasks;
  final ValueChanged<CalendarTask> onTaskTap;
  final ValueChanged<DateTime>? onEmptyTap;

  /// 表示専用（未ダウンロード）の Google イベントを長押しで動かそうとしたときの通知。
  final ValueChanged<CalendarTask>? onReadOnlyMoveAttempt;

  /// 「タスク」として扱うブロックのID集合。空ならすべて非タスク扱い。
  /// このIDに含まれるブロックは周囲に太枠を描画する。
  final Set<String> taskIds;

  @override
  ConsumerState<WeekSchedulePanel> createState() => _WeekSchedulePanelState();
}

class _WeekSchedulePanelState extends ConsumerState<WeekSchedulePanel> {
  static const double _defaultHourHeight = 48.0;
  static const double _minHourHeight = 24.0;
  static const double _maxHourHeight = 120.0;
  static const double _gutterWidth = 40.0;
  static const double _allDayRowHeight = 28.0;
  static const double _dayHeaderHeight = 32.0;
  static const int _startHour = 0;
  static const int _endHour = 24;

  final ScrollController _scrollController = ScrollController();
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  bool _didInitialScroll = false;

  double _hourHeight = _defaultHourHeight;
  double _pinchStartHourHeight = _defaultHourHeight;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
  }

  void _scrollToNow() {
    if (_didInitialScroll) return;
    if (!_scrollController.hasClients) return;
    final target = ((_now.hour - 1).clamp(0, 23)) * _hourHeight;
    _scrollController.jumpTo(target);
    _didInitialScroll = true;
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onMoveTask(CalendarTask task, DateTime newStart) async {
    final vm = ref.read(calendarSyncViewModelProvider.notifier);
    final success = await vm.moveTask(task, newStart);
    if (!mounted) return;
    if (!success) {
      final msg = ref.read(calendarSyncViewModelProvider).errorMessage;
      showAppSnackBar(
        context,
        SnackBar(content: Text(msg ?? '移動に失敗しました')),
      );
      vm.clearError();
    }
  }

  int? _todayIndexInRange() {
    final today = DateTime(_now.year, _now.month, _now.day);
    for (var i = 0; i < widget.visibleDays.length; i++) {
      final d = widget.visibleDays[i];
      final norm = DateTime(d.year, d.month, d.day);
      if (norm == today) return i;
    }
    return null;
  }

  List<List<CalendarTask>> _splitByDay() {
    final days = widget.visibleDays;
    // 日付正規化をループ前に1回だけ計算する（タスク数 × days数 の繰り返しを防ぐ）。
    final normalizedDays = List.generate(
      days.length,
      (i) => DateTime(days[i].year, days[i].month, days[i].day),
      growable: false,
    );
    final result = List<List<CalendarTask>>.generate(days.length, (_) => []);
    for (final t in widget.tasks) {
      final ts = t.start;
      if (ts == null || t.end == null) {
        continue; // ToDo項目や start/end 欠損はカレンダー表示対象外
      }
      final taskDay = DateTime(ts.year, ts.month, ts.day);
      for (var i = 0; i < days.length; i++) {
        if (normalizedDays[i] == taskDay) {
          result[i].add(t);
          break;
        }
      }
    }
    for (final list in result) {
      list.sort((a, b) => a.start!.compareTo(b.start!));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dayFmt = DateFormat.Md('ja_JP');
    final days = _splitByDay();
    final visibleDays = widget.visibleDays;
    final dayCount = visibleDays.length;
    final totalHours = _endHour - _startHour;
    final gridHeight = totalHours * _hourHeight;
    final hasAllDay = days.any((list) => list.any((t) => t.isAllDay));
    final calendarColors = ref.watch(calendarColorsProvider);
    final todayIdx = _todayIndexInRange();

    // データが来てからスクロール位置を合わせる（初回のみ）
    if (!_didInitialScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          // ── 日付ヘッダー ──────────────────────────
          SizedBox(
            height: _dayHeaderHeight,
            child: Row(
              children: [
                const SizedBox(width: _gutterWidth),
                ...List.generate(dayCount, (i) {
                  final day = visibleDays[i];
                  final isToday = todayIdx == i;
                  return Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                              color: Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.35)),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${DateFormat.E('ja_JP').format(day)} ${dayFmt.format(day)}',
                          style: text.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isToday ? scheme.primary : null,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── 終日バナー ────────────────────────────
          if (hasAllDay) ...[
            SizedBox(
              height: _allDayRowHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: _gutterWidth,
                    child: Center(
                      child: Text(
                        '終日',
                        style: text.labelSmall?.copyWith(
                            fontSize: 10, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  ...List.generate(dayCount, (i) {
                    final allDayTasks =
                        days[i].where((t) => t.isAllDay).toList();
                    return Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                                color: Theme.of(context)
                                    .dividerColor
                                    .withValues(alpha: 0.35)),
                          ),
                        ),
                        child: Row(
                          children: allDayTasks.map((t) {
                            final isTask = widget.taskIds.contains(t.id);
                            final color = resolveTaskColor(
                                t, calendarColors, scheme,
                                isManaged: isTask);
                            final completed = t.isCompleted;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => widget.onTaskTap(t),
                                child: Container(
                                  margin: const EdgeInsets.all(2),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: color.withValues(
                                        alpha: completed ? 0.12 : 0.22),
                                    borderRadius: BorderRadius.circular(4),
                                    border: isTask
                                        ? Border.all(color: color, width: 2)
                                        : Border(
                                            left: BorderSide(
                                                color: color, width: 3)),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    t.title,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      decoration: completed
                                          ? TextDecoration.lineThrough
                                          : null,
                                      decorationThickness: 2.0,
                                      color: completed
                                          ? Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.color
                                              ?.withValues(alpha: 0.6)
                                          : null,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const Divider(height: 1),
          ],

          // ── 時間グリッド（スクロール + ピンチで時間高さ拡縮） ──
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onScaleStart: (details) {
                if (details.pointerCount < 2) return;
                _pinchStartHourHeight = _hourHeight;
              },
              onScaleUpdate: (details) {
                if (details.pointerCount < 2) return;
                final next = (_pinchStartHourHeight * details.scale)
                    .clamp(_minHourHeight, _maxHourHeight);
                if (next != _hourHeight) {
                  setState(() => _hourHeight = next);
                }
              },
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SizedBox(
                  height: gridHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 時刻ガター
                    SizedBox(
                      width: _gutterWidth,
                      child: Column(
                        children: List.generate(totalHours, (i) {
                          final h = _startHour + i;
                          return SizedBox(
                            height: _hourHeight,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2, right: 6),
                              child: Text(
                                h == 0 ? '' : '$h:00',
                                style: text.labelSmall?.copyWith(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    // 可変日数のカラム
                    ...List.generate(dayCount, (i) {
                      final dayDate = visibleDays[i];
                      return Expanded(
                        child: _DayColumn(
                          dayDate: dayDate,
                          tasks: days[i].where((t) => !t.isAllDay).toList(),
                          hourHeight: _hourHeight,
                          startHour: _startHour,
                          endHour: _endHour,
                          onTaskTap: widget.onTaskTap,
                          onMoveTask: _onMoveTask,
                          onEmptyTap: widget.onEmptyTap,
                          onReadOnlyMoveAttempt: widget.onReadOnlyMoveAttempt,
                          calendarColors: calendarColors,
                          isToday: todayIdx == i,
                          now: _now,
                          taskIds: widget.taskIds,
                        ),
                      );
                    }),
                  ],
                ),
              ),
              ),
            ),
          ),
        ],
    );
  }
}

class _DayColumn extends ConsumerWidget {
  const _DayColumn({
    required this.dayDate,
    required this.tasks,
    required this.hourHeight,
    required this.startHour,
    required this.endHour,
    required this.onTaskTap,
    required this.onMoveTask,
    required this.onEmptyTap,
    required this.onReadOnlyMoveAttempt,
    required this.calendarColors,
    required this.isToday,
    required this.now,
    required this.taskIds,
  });

  final DateTime dayDate;
  final List<CalendarTask> tasks;
  final double hourHeight;
  final int startHour;
  final int endHour;
  final ValueChanged<CalendarTask> onTaskTap;
  final void Function(CalendarTask task, DateTime newStart) onMoveTask;
  final ValueChanged<DateTime>? onEmptyTap;
  final ValueChanged<CalendarTask>? onReadOnlyMoveAttempt;
  final Map<String, Color> calendarColors;
  final bool isToday;
  final DateTime now;
  final Set<String> taskIds;

  DateTime _computeTimeFromLocalY(double localY) {
    final rangeStartMin = startHour * 60;
    final rangeEndMin = endHour * 60;
    final minutesFromStart = (localY / hourHeight * 60).round();
    var totalMinutes = rangeStartMin + minutesFromStart;
    totalMinutes = (totalMinutes / 15).round() * 15;
    totalMinutes = totalMinutes.clamp(rangeStartMin, rangeEndMin - 15);
    final hour = totalMinutes ~/ 60;
    final minute = totalMinutes % 60;
    return DateTime(dayDate.year, dayDate.month, dayDate.day, hour, minute);
  }

  DateTime _computeDropStart(BuildContext context, Offset globalOffset) {
    final box = context.findRenderObject() as RenderBox?;
    final localY = box == null ? 0.0 : box.globalToLocal(globalOffset).dy;
    return _computeTimeFromLocalY(localY);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final totalHours = endHour - startHour;
    final rangeStartMin = startHour * 60;
    final rangeEndMin = endHour * 60;
    final layouts = _layoutTasks(tasks);
    // ドラッグ中のウィジェット破棄後でも安全に呼べるよう、Notifier をここでキャプチャ
    final dragNotifier = ref.read(isDraggingTaskProvider.notifier);

    return DragTarget<CalendarTask>(
      onAcceptWithDetails: (details) {
        final newStart = _computeDropStart(context, details.offset);
        onMoveTask(details.data, newStart);
      },
      builder: (context, candidate, rejected) {
        final isHovering = candidate.isNotEmpty;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: onEmptyTap == null
              ? null
              : (details) {
                  final newStart =
                      _computeTimeFromLocalY(details.localPosition.dy);
                  onEmptyTap!(newStart);
                },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isHovering
                  ? scheme.primary.withValues(alpha: 0.06)
                  : Colors.transparent,
              border: Border(
                left: BorderSide(
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.35)),
              ),
            ),
            child: LayoutBuilder(
            builder: (context, constraints) {
              final totalW = constraints.maxWidth;
              return Stack(
                children: [
                  // 時間ライン
                  ...List.generate(totalHours, (i) {
                    return Positioned(
                      top: i * hourHeight,
                      left: 0,
                      right: 0,
                      height: 1,
                      child: ColoredBox(
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.18),
                      ),
                    );
                  }),
                  // タスク
                  ...layouts.map((entry) {
                    final task = entry.$1;
                    final lane = entry.$2;
                    final laneCount = entry.$3;
                    final startMin =
                        task.start!.hour * 60 + task.start!.minute;
                    final endMin = task.end!.hour * 60 + task.end!.minute;
                    final clipStart =
                        startMin.clamp(rangeStartMin, rangeEndMin);
                    final clipEnd = endMin.clamp(rangeStartMin, rangeEndMin);
                    if (clipEnd <= clipStart) return const SizedBox.shrink();
                    final top = (clipStart - rangeStartMin) / 60 * hourHeight;
                    final rawHeight =
                        (clipEnd - clipStart) / 60 * hourHeight;
                    final height = rawHeight < 18 ? 18.0 : rawHeight;
                    final isTask = taskIds.contains(task.id);
                    final color = resolveTaskColor(
                        task, calendarColors, scheme,
                        isManaged: isTask);
                    final laneW = totalW / laneCount;
                    final cardWidth = laneW - 2;

                    final completed = task.isCompleted;
                    final taskCard = Material(
                      color: color.withValues(
                          alpha: completed ? 0.12 : 0.22),
                      borderRadius: BorderRadius.circular(4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => onTaskTap(task),
                        child: Container(
                          decoration: BoxDecoration(
                            border: isTask
                                ? Border.all(
                                    color: color.withValues(
                                        alpha: completed ? 0.6 : 1.0),
                                    width: 2)
                                : Border(
                                    left:
                                        BorderSide(color: color, width: 3)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Text(
                            task.title,
                            style: text.bodySmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              decoration: completed
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationThickness: 2.0,
                              color: completed
                                  ? text.bodySmall?.color
                                      ?.withValues(alpha: 0.6)
                                  : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines:
                                ((height - 4) / 13).floor().clamp(1, 4),
                          ),
                        ),
                      ),
                    );

                    return Positioned(
                      top: top,
                      left: lane * laneW + 1,
                      width: cardWidth,
                      height: height,
                      child: isTask
                          ? LongPressDraggable<CalendarTask>(
                              data: task,
                              delay: const Duration(milliseconds: 300),
                              dragAnchorStrategy: childDragAnchorStrategy,
                              onDragStarted: () =>
                                  dragNotifier.setDragging(true),
                              onDragEnd: (_) =>
                                  dragNotifier.setDragging(false),
                              onDraggableCanceled: (_, _) =>
                                  dragNotifier.setDragging(false),
                              onDragCompleted: () =>
                                  dragNotifier.setDragging(false),
                              feedback: Material(
                                color: Colors.transparent,
                                child: Container(
                                  width: cardWidth,
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black38,
                                        blurRadius: 8,
                                        offset: Offset(2, 4),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  child: Text(
                                    task.title,
                                    style: text.bodySmall?.copyWith(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: ((height - 4) / 13)
                                        .floor()
                                        .clamp(1, 4),
                                  ),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.3,
                                child: taskCard,
                              ),
                              child: taskCard,
                            )
                          // 表示専用（未ダウンロード）の Google イベントは
                          // ドラッグ不可。長押し（＝移動操作）のときだけ案内を出す。
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPress: onReadOnlyMoveAttempt == null
                                  ? null
                                  : () => onReadOnlyMoveAttempt!(task),
                              child: taskCard,
                            ),
                    );
                  }),
                  // 現在時刻ライン（今日の列のみ）
                  if (isToday)
                    ..._buildNowIndicator(
                        rangeStartMin, rangeEndMin, hourHeight),
                ],
              );
            },
          ),
          ),
        );
      },
    );
  }

  List<Widget> _buildNowIndicator(
      int rangeStartMin, int rangeEndMin, double hourHeight) {
    final nowMin = now.hour * 60 + now.minute;
    if (nowMin < rangeStartMin || nowMin > rangeEndMin) return const [];
    final y = (nowMin - rangeStartMin) / 60 * hourHeight;
    return [
      Positioned(
        top: y - 1,
        left: 0,
        right: 0,
        height: 2,
        child: const ColoredBox(color: Colors.red),
      ),
      Positioned(
        top: y - 4,
        left: -4,
        width: 8,
        height: 8,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
        ),
      ),
    ];
  }
}

/// 日内タスクのレーン割り当て。連続して重なるタスクは同じグループ内で
/// 横並びレーンになる。返り値は (task, laneIndex, laneCount)。
List<(CalendarTask, int, int)> _layoutTasks(List<CalendarTask> tasks) {
  // start/end が null のタスクはここに来ない想定だが、安全のため除外
  final filtered = tasks.where((t) => t.start != null && t.end != null).toList();
  if (filtered.isEmpty) return const [];
  final sorted = [...filtered]..sort((a, b) => a.start!.compareTo(b.start!));
  final result = <(CalendarTask, int, int)>[];

  var groupStart = 0;
  var groupEnd = sorted.first.end!;

  void flushGroup(int startIdx, int endIdxExclusive) {
    final group = sorted.sublist(startIdx, endIdxExclusive);
    final laneEnds = <DateTime>[];
    final assignments = List<int>.filled(group.length, 0);
    for (var i = 0; i < group.length; i++) {
      final t = group[i];
      var lane = -1;
      for (var j = 0; j < laneEnds.length; j++) {
        if (!laneEnds[j].isAfter(t.start!)) {
          lane = j;
          laneEnds[j] = t.end!;
          break;
        }
      }
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(t.end!);
      }
      assignments[i] = lane;
    }
    final laneCount = laneEnds.length;
    for (var i = 0; i < group.length; i++) {
      result.add((group[i], assignments[i], laneCount));
    }
  }

  for (var i = 1; i < sorted.length; i++) {
    final t = sorted[i];
    if (t.start!.isBefore(groupEnd)) {
      if (t.end!.isAfter(groupEnd)) groupEnd = t.end!;
    } else {
      flushGroup(groupStart, i);
      groupStart = i;
      groupEnd = t.end!;
    }
  }
  flushGroup(groupStart, sorted.length);
  return result;
}

/// タスクの色を解決する。
/// managed（Firestore 管理下）なら象限色、未管理 Google イベントならカレンダー色。
Color resolveTaskColor(
  CalendarTask task,
  Map<String, Color> calendarColors,
  ColorScheme scheme, {
  bool isManaged = false,
}) {
  if (isManaged) {
    final q = QuadrantX.from(
        urgency: task.urgency, importance: task.importance);
    return q.accentColor(scheme);
  }
  if (task.sourceType == TaskSourceType.googleCalendar &&
      task.externalCalendarId != null) {
    final raw = task.externalCalendarId!;
    final idx = raw.indexOf(':');
    final calId = idx > 0 ? raw.substring(0, idx) : null;
    if (calId != null && calendarColors[calId] != null) {
      return calendarColors[calId]!;
    }
    return Colors.blueGrey;
  }
  return scheme.primary;
}
