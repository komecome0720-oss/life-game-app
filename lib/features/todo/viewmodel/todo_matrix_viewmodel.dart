import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  Future<void> createTodo(
    String title, {
    Quadrant quadrant = Quadrant.notUrgentImportant,
  }) async {
    final titleTrim = title.trim();
    if (titleTrim.isEmpty) return;
    final repo = ref.read(todoRepositoryProvider);
    // 先頭に出したいので orderIndex=0、既存は自然に後ろへ
    await repo.createTodo(
      title: titleTrim,
      urgency: quadrant.urgency,
      importance: quadrant.importance,
      orderIndex: 0,
    );
  }

  Future<void> updateTodo(CalendarTask task) async {
    await ref.read(todoRepositoryProvider).upsert(task);
  }

  Future<void> moveToQuadrant(CalendarTask task, Quadrant q) async {
    await ref.read(todoRepositoryProvider).updateQuadrant(
          task.id,
          urgency: q.urgency,
          importance: q.importance,
          orderIndex: task.orderIndex,
        );
  }

  Future<void> delete(String id) async {
    await ref.read(todoRepositoryProvider).delete(id);
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

final todoMatrixViewModelProvider =
    Provider<TodoMatrixViewModel>((ref) => TodoMatrixViewModel(ref));
