import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/todo/data/todo_repository.dart';
import 'package:task_manager/models/calendar_task.dart';

final todoRepositoryProvider = Provider<TodoRepository>((_) => TodoRepository());

/// ToDo タスク一覧のストリーム。
final todosStreamProvider = StreamProvider.autoDispose<List<CalendarTask>>((ref) {
  return ref.watch(todoRepositoryProvider).watchTodos();
});

/// ドラッグ中のタスク（クロスタブドラッグのヒント表示に使用）。
class DraggingTodoNotifier extends Notifier<CalendarTask?> {
  @override
  CalendarTask? build() => null;
  void setDragging(CalendarTask? task) => state = task;
}

final draggingTodoProvider =
    NotifierProvider<DraggingTodoNotifier, CalendarTask?>(
  DraggingTodoNotifier.new,
);

/// ドラッグ中のポインタ絶対座標（必要に応じてカスタム Overlay 等で使用）。
class DragPositionNotifier extends Notifier<Offset?> {
  @override
  Offset? build() => null;
  void set(Offset? o) => state = o;
}

final dragPositionProvider =
    NotifierProvider<DragPositionNotifier, Offset?>(DragPositionNotifier.new);

/// MainShell の現在タブ index。ToDo → カレンダー ドロップ時にプログラムから切替える。
class MainTabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int v) => state = v;
}

final mainTabIndexProvider =
    NotifierProvider<MainTabIndexNotifier, int>(MainTabIndexNotifier.new);
