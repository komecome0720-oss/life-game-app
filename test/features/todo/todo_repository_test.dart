import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/todo/data/todo_repository.dart';
import 'package:task_manager/models/calendar_task.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  const uid = 'test-uid';

  late FakeFirebaseFirestore firestore;
  late TodoRepository repo;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    repo = TodoRepository(db: firestore, auth: auth);

    await firestore
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc('task1')
        .set({
      'title': '元のタイトル',
      'reward': 0,
      'sourceType': 'manual',
      'isAllDay': false,
      'isCompleted': false,
      'isTodo': true,
      'urgency': true,
      'importance': true,
      'orderIndex': 0,
      'estimatedMinutes': 30,
    });
  });

  test(
    'upsertAndConvertToCalendarEventが1回の呼び出しで編集内容とカレンダー変換を両方書き込む',
    () async {
      const task = CalendarTask(
        id: 'task1',
        title: '完了したタスク',
        start: null,
        end: null,
        rewardYen: 0,
        urgency: false,
        importance: true,
        orderIndex: 2,
        estimatedMinutes: 45,
        note: 'メモ',
        description: '詳細説明',
      );
      final start = DateTime(2026, 7, 7, 9, 0);
      final end = DateTime(2026, 7, 7, 9, 45);

      await repo.upsertAndConvertToCalendarEvent(
        task: task,
        start: start,
        end: end,
      );

      final doc = await firestore
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc('task1')
          .get();
      final data = doc.data()!;

      expect(data['title'], '完了したタスク');
      expect(data['urgency'], false);
      expect(data['importance'], true);
      expect(data['orderIndex'], 2);
      expect(data['estimatedMinutes'], 45);
      expect(data['note'], 'メモ');
      expect(data['description'], '詳細説明');
      expect(data['isTodo'], false);
      expect(
        (data['startAtUtc'] as Timestamp).toDate().isAtSameMomentAs(
              start.toUtc(),
            ),
        isTrue,
      );
      expect(
        (data['endAtUtc'] as Timestamp).toDate().isAtSameMomentAs(end.toUtc()),
        isTrue,
      );
    },
  );

  test('既存のupsert単体呼び出しが引き続き動作する（回帰確認）', () async {
    const task = CalendarTask(
      id: 'task1',
      title: '編集後タイトル',
      start: null,
      end: null,
      rewardYen: 0,
      estimatedMinutes: 20,
    );

    await repo.upsert(task);

    final doc = await firestore
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc('task1')
        .get();
    expect(doc.data()?['title'], '編集後タイトル');
    // カレンダー変換フィールドは書き込まれていないこと。
    expect(doc.data()?.containsKey('startAtUtc'), isFalse);
  });

  test('既存のconvertToCalendarEvent単体呼び出しが引き続き動作する（回帰確認）', () async {
    final start = DateTime(2026, 7, 7, 8, 0);
    final end = DateTime(2026, 7, 7, 8, 30);

    await repo.convertToCalendarEvent(taskId: 'task1', start: start, end: end);

    final doc = await firestore
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc('task1')
        .get();
    expect(doc.data()?['isTodo'], false);
    expect(
      (doc.data()?['startAtUtc'] as Timestamp).toDate().isAtSameMomentAs(
            start.toUtc(),
          ),
      isTrue,
    );
  });
}
