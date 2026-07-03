import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';

CalendarTask _task(String id) => CalendarTask(
  id: id,
  title: id,
  start: null,
  end: null,
  rewardYen: 0,
  isTodo: true,
);

List<String> _ids(List<CalendarTask> tasks) => tasks.map((t) => t.id).toList();

void main() {
  group('computeReorderedList', () {
    final a = _task('a');
    final b = _task('b');
    final c = _task('c');
    final d = _task('d');
    final e = _task('e');

    test('同一象限：下方向へ移動（前カードの後ろに挿入）', () {
      // [A,B,C,D,E] で C(index2) を D(index3) の後ろ半分にドロップ = insertIndex 4
      final result = computeReorderedList(
        quadrantTasks: [a, b, c, d, e],
        dragged: c,
        insertIndex: 4,
      );
      expect(_ids(result!), ['a', 'b', 'd', 'c', 'e']);
    });

    test('同一象限：上方向へ移動', () {
      // [A,B,C,D,E] で E(index4) を B(index1) の後ろ半分にドロップ = insertIndex 2
      final result = computeReorderedList(
        quadrantTasks: [a, b, c, d, e],
        dragged: e,
        insertIndex: 2,
      );
      expect(_ids(result!), ['a', 'b', 'e', 'c', 'd']);
    });

    test('自分自身の前半分（＝現在位置）へのドロップは no-op', () {
      final result = computeReorderedList(
        quadrantTasks: [a, b, c, d, e],
        dragged: c,
        insertIndex: 2,
      );
      expect(result, isNull);
    });

    test('自分自身の後半分（＝隣接ギャップ）へのドロップも no-op', () {
      final result = computeReorderedList(
        quadrantTasks: [a, b, c, d, e],
        dragged: c,
        insertIndex: 3,
      );
      expect(result, isNull);
    });

    test('最後尾タスクを末尾（象限全体の外側ターゲット）にドロップしても no-op', () {
      final result = computeReorderedList(
        quadrantTasks: [a, b, c, d, e],
        dragged: e,
        insertIndex: 5,
      );
      expect(result, isNull);
    });

    test('他象限からの挿入：先頭', () {
      final result = computeReorderedList(
        quadrantTasks: [a, b, c],
        dragged: d,
        insertIndex: 0,
      );
      expect(_ids(result!), ['d', 'a', 'b', 'c']);
    });

    test('他象限からの挿入：中間', () {
      final result = computeReorderedList(
        quadrantTasks: [a, b, c],
        dragged: d,
        insertIndex: 1,
      );
      expect(_ids(result!), ['a', 'd', 'b', 'c']);
    });

    test('他象限からの挿入：末尾', () {
      final result = computeReorderedList(
        quadrantTasks: [a, b, c],
        dragged: d,
        insertIndex: 3,
      );
      expect(_ids(result!), ['a', 'b', 'c', 'd']);
    });

    test('他象限からの挿入：空の象限へ', () {
      final result = computeReorderedList(
        quadrantTasks: const [],
        dragged: a,
        insertIndex: 0,
      );
      expect(_ids(result!), ['a']);
    });
  });

  group('estimatedMinutesFromRange', () {
    CalendarTask calendarTask({
      DateTime? start,
      DateTime? end,
      bool isAllDay = false,
    }) => CalendarTask(
      id: 'x',
      title: 'x',
      start: start,
      end: end,
      rewardYen: 0,
      isAllDay: isAllDay,
    );

    test('start/end の分数をそのまま返す', () {
      final task = calendarTask(
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 1, 11, 30),
      );
      expect(estimatedMinutesFromRange(task), 90);
    });

    test('start/end が欠損していればデフォルト30分', () {
      expect(estimatedMinutesFromRange(calendarTask()), 30);
    });

    test('終日イベントはデフォルト30分', () {
      final task = calendarTask(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 2),
        isAllDay: true,
      );
      expect(estimatedMinutesFromRange(task), 30);
    });

    test('end が start 以前（異常値）はデフォルト30分', () {
      final task = calendarTask(
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 11),
      );
      expect(estimatedMinutesFromRange(task), 30);
    });
  });
}
