import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/models/calendar_task.dart';

/// ToDo マトリクスの4象限。urgency×importance の組合せをキーにする。
enum Quadrant {
  urgentImportant, // 右上: 緊急 × 重要
  notUrgentImportant, // 右下: 非緊急 × 重要
  urgentNotImportant, // 左上: 緊急 × 非重要
  notUrgentNotImportant, // 左下: 非緊急 × 非重要
}

extension QuadrantX on Quadrant {
  bool get urgency =>
      this == Quadrant.urgentImportant || this == Quadrant.urgentNotImportant;
  bool get importance =>
      this == Quadrant.urgentImportant || this == Quadrant.notUrgentImportant;

  /// 領域番号（標準アイゼンハワー: 緊急・重要=1, ×緊急・重要=2,
  /// 緊急・×重要=3, ×緊急・×重要=4）。
  int get number {
    switch (this) {
      case Quadrant.urgentImportant:
        return 1;
      case Quadrant.notUrgentImportant:
        return 2;
      case Quadrant.urgentNotImportant:
        return 3;
      case Quadrant.notUrgentNotImportant:
        return 4;
    }
  }

  /// 「×緊急・重要」形式の象限説明（× は否定を示す）。
  String get adjectives {
    switch (this) {
      case Quadrant.urgentImportant:
        return '緊急・重要';
      case Quadrant.urgentNotImportant:
        return '緊急・×重要';
      case Quadrant.notUrgentImportant:
        return '×緊急・重要';
      case Quadrant.notUrgentNotImportant:
        return '×緊急・×重要';
    }
  }

  /// 「1（×緊急・重要）」形式の表示ラベル。
  String get label => '$number（$adjectives）';

  Color accentColor([ColorScheme? scheme]) {
    switch (this) {
      case Quadrant.urgentImportant:
        return Colors.red.shade600;
      case Quadrant.notUrgentImportant:
        return Colors.amber.shade700;
      case Quadrant.urgentNotImportant:
        return Colors.lightBlue.shade700;
      case Quadrant.notUrgentNotImportant:
        return scheme?.onSurfaceVariant ?? Colors.grey.shade600;
    }
  }

  Color backgroundColor([ColorScheme? scheme]) {
    switch (this) {
      case Quadrant.urgentImportant:
        return Colors.red.withValues(alpha: 0.08);
      case Quadrant.notUrgentImportant:
        return Colors.yellow.withValues(alpha: 0.18);
      case Quadrant.urgentNotImportant:
        return Colors.lightBlue.withValues(alpha: 0.14);
      case Quadrant.notUrgentNotImportant:
        return (scheme?.surfaceContainerHighest ?? Colors.grey.shade200)
            .withValues(alpha: 0.4);
    }
  }

  static Quadrant from({required bool urgency, required bool importance}) {
    if (urgency && importance) return Quadrant.urgentImportant;
    if (!urgency && importance) return Quadrant.notUrgentImportant;
    if (urgency && !importance) return Quadrant.urgentNotImportant;
    return Quadrant.notUrgentNotImportant;
  }

  /// 領域番号 1〜4 から Quadrant を取得。範囲外はデフォルト(1)。
  static Quadrant fromNumber(int n) {
    switch (n) {
      case 2:
        return Quadrant.notUrgentImportant;
      case 3:
        return Quadrant.urgentNotImportant;
      case 4:
        return Quadrant.notUrgentNotImportant;
      case 1:
      default:
        return Quadrant.urgentImportant;
    }
  }
}

class TodoMatrixViewModel {
  TodoMatrixViewModel(this.ref);
  final Ref ref;

  /// 新規 ToDo を作成。[quadrant] 省略時は領域1（×緊急・重要）。
  /// 象限の先頭に出すため、既存タスクの最小 orderIndex - 1 を採番する
  /// （0 固定だと手動並び替え後の既存タスクとタイになり順序が不安定になるため）。
  Future<void> createTodo(
    String title, {
    Quadrant quadrant = Quadrant.notUrgentImportant,
  }) async {
    final titleTrim = title.trim();
    if (titleTrim.isEmpty) return;
    final repo = ref.read(todoRepositoryProvider);
    final all = ref.read(todosStreamProvider).asData?.value ?? const [];
    final quadrantTasks = filterByQuadrant(all, quadrant);
    final minIndex = quadrantTasks.isEmpty
        ? 0
        : quadrantTasks.map((t) => t.orderIndex).reduce((a, b) => a < b ? a : b) - 1;
    await repo.createTodo(
      title: titleTrim,
      urgency: quadrant.urgency,
      importance: quadrant.importance,
      orderIndex: minIndex,
    );
  }

  Future<void> updateTodo(CalendarTask task) async {
    await ref.read(todoRepositoryProvider).upsert(task);
  }

  /// [dragged] を [quadrant] の [quadrantTasks]（画面表示中の並び）における
  /// [insertIndex] 位置に挿入する。並びも象限も変わらなければ何もしない。
  Future<void> reorderTask({
    required CalendarTask dragged,
    required Quadrant quadrant,
    required List<CalendarTask> quadrantTasks,
    required int insertIndex,
  }) async {
    final reordered = computeReorderedList(
      quadrantTasks: quadrantTasks,
      dragged: dragged,
      insertIndex: insertIndex,
    );
    if (reordered == null) return;
    await ref.read(todoRepositoryProvider).applyQuadrantOrder(
          orderedTasks: reordered,
          movedTaskId: dragged.id,
          urgency: quadrant.urgency,
          importance: quadrant.importance,
        );
  }

  Future<void> delete(String id) async {
    await ref.read(todoRepositoryProvider).delete(id);
  }

  /// カレンダー予定（[dragged]、isTodo=false）を ToDo 化して [quadrant] の末尾に追加する。
  /// 所要時間は元の start/end の分数（欠損・終日等は既存デフォルト30分）。
  Future<void> convertCalendarTaskToTodo({
    required CalendarTask dragged,
    required Quadrant quadrant,
    required List<CalendarTask> quadrantTasks,
  }) async {
    final orderIndex = quadrantTasks.isEmpty
        ? 0
        : quadrantTasks.map((t) => t.orderIndex).reduce((a, b) => a > b ? a : b) + 1;
    await ref.read(calendarTaskSyncRepositoryProvider).convertToTodo(
          taskId: dragged.id,
          urgency: quadrant.urgency,
          importance: quadrant.importance,
          orderIndex: orderIndex,
          estimatedMinutes: estimatedMinutesFromRange(dragged),
        );
  }

  /// 指定象限に属するタスクのみ抽出（orderIndex 昇順）。
  List<CalendarTask> filterByQuadrant(
      List<CalendarTask> all, Quadrant q) {
    return all
        .where((t) => t.urgency == q.urgency && t.importance == q.importance)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }
}

/// [quadrantTasks]（移動先象限の現在の並び。[dragged] が他象限からの移動なら
/// 含まれない）から [dragged] を [insertIndex] の位置に挿入した新しい並びを返す。
/// 挿入結果が変化なし（同じ位置への同象限内ドロップ等）の場合は null を返す。
List<CalendarTask>? computeReorderedList({
  required List<CalendarTask> quadrantTasks,
  required CalendarTask dragged,
  required int insertIndex,
}) {
  final working = List<CalendarTask>.of(quadrantTasks);
  final oldIndex = working.indexWhere((t) => t.id == dragged.id);
  var target = insertIndex;
  if (oldIndex != -1) {
    working.removeAt(oldIndex);
    if (oldIndex < target) target -= 1;
  }
  target = target.clamp(0, working.length);
  if (oldIndex == target) return null;
  working.insert(target, dragged);
  return working;
}

/// カレンダー予定の start/end から ToDo 化時の estimatedMinutes を算出する。
/// start/end 欠損・終日・0分以下等の異常値は既存デフォルトの30分とする。
int estimatedMinutesFromRange(CalendarTask task) {
  final start = task.start;
  final end = task.end;
  if (task.isAllDay || start == null || end == null) return 30;
  final minutes = end.difference(start).inMinutes;
  return minutes > 0 ? minutes : 30;
}

final todoMatrixViewModelProvider =
    Provider<TodoMatrixViewModel>((ref) => TodoMatrixViewModel(ref));
