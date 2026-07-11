import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/calendar_sync/data/calendar_task_sync_repository.dart';
import 'package:task_manager/models/calendar_task.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  const uid = 'test-uid';

  late FakeFirebaseFirestore firestore;
  late CalendarTaskSyncRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    repo = CalendarTaskSyncRepository(db: firestore, auth: auth);
  });

  Future<Map<String, dynamic>> taskDataByExternalId(String externalId) async {
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .where('externalCalendarId', isEqualTo: externalId)
        .get();
    expect(snap.docs.length, 1);
    return snap.docs.first.data();
  }

  group('upsert', () {
    test('未存在のexternalCalendarIdは新規作成される', () async {
      final task = CalendarTask(
        id: 'ignored',
        title: '会議',
        start: DateTime(2026, 7, 6, 10),
        end: DateTime(2026, 7, 6, 11),
        rewardYen: 0,
        externalCalendarId: 'cal1:evt1',
      );

      await repo.upsert([task]);

      final data = await taskDataByExternalId('cal1:evt1');
      expect(data['title'], '会議');
    });

    test('既存のexternalCalendarIdは更新され、isCompleted等ユーザー操作値は保持される', () async {
      await firestore.collection('users').doc(uid).collection('tasks').add({
        'title': '旧タイトル',
        'externalCalendarId': 'cal1:evt1',
        'isCompleted': true,
        'actualMinutes': 45,
        'isTodo': false,
      });

      final updated = CalendarTask(
        id: 'ignored',
        title: '新タイトル',
        start: DateTime(2026, 7, 6, 10),
        end: DateTime(2026, 7, 6, 11),
        rewardYen: 0,
        externalCalendarId: 'cal1:evt1',
      );
      await repo.upsert([updated]);

      final data = await taskDataByExternalId('cal1:evt1');
      expect(data['title'], '新タイトル');
      expect(data['isCompleted'], isTrue, reason: '完了状態はGoogle側の再取得で巻き戻してはいけない');
      expect(data['actualMinutes'], 45, reason: '実績ログはGoogle側の再取得で巻き戻してはいけない');
    });

    test('ToDo化済み（isTodo=true）は更新をスキップする', () async {
      await firestore.collection('users').doc(uid).collection('tasks').add({
        'title': 'ToDo化済み',
        'externalCalendarId': 'cal1:evt1',
        'isTodo': true,
      });

      final updated = CalendarTask(
        id: 'ignored',
        title: 'Google側の新タイトル',
        start: DateTime(2026, 7, 6, 10),
        end: DateTime(2026, 7, 6, 11),
        rewardYen: 0,
        externalCalendarId: 'cal1:evt1',
      );
      await repo.upsert([updated]);

      final data = await taskDataByExternalId('cal1:evt1');
      expect(data['title'], 'ToDo化済み', reason: 'ToDo化済みはGoogle側データで巻き戻されてはいけない');
    });

    test('repositioned=true（実績ベースで再配置済み）は isCompleted の真偽に依らず更新をスキップする',
        () async {
      await firestore.collection('users').doc(uid).collection('tasks').add({
        'title': '再配置済み',
        'externalCalendarId': 'cal1:evt1',
        'isTodo': false,
        'isCompleted': false, // 完了確定前の非同期窓を想定
        'repositioned': true,
        'startAtUtc': DateTime(2026, 7, 6, 10, 30).toUtc(),
        'endAtUtc': DateTime(2026, 7, 6, 11).toUtc(),
      });

      final updated = CalendarTask(
        id: 'ignored',
        title: 'Google側の新タイトル',
        start: DateTime(2026, 7, 6, 10),
        end: DateTime(2026, 7, 6, 11),
        rewardYen: 0,
        externalCalendarId: 'cal1:evt1',
      );
      await repo.upsert([updated]);

      final data = await taskDataByExternalId('cal1:evt1');
      expect(data['title'], '再配置済み', reason: 'repositioned:true はGoogle側データで巻き戻されてはいけない');
      expect(
        (data['startAtUtc'] as Timestamp)
            .toDate()
            .isAtSameMomentAs(DateTime(2026, 7, 6, 10, 30).toUtc()),
        isTrue,
      );
    });
  });

  group('deleteTasksByCalendarInWeek', () {
    test('指定週・指定カレンダーの未着手タスクのみ削除する', () async {
      final weekStart = DateTime(2026, 7, 6);
      final tasksCol =
          firestore.collection('users').doc(uid).collection('tasks');

      await tasksCol.add({
        'title': '対象（削除される）',
        'externalCalendarId': 'calA:evt1',
        'startAtUtc': DateTime(2026, 7, 7).toUtc(),
        'isCompleted': false,
      });
      await tasksCol.add({
        'title': '完了済み（保護される）',
        'externalCalendarId': 'calA:evt2',
        'startAtUtc': DateTime(2026, 7, 7).toUtc(),
        'isCompleted': true,
      });
      await tasksCol.add({
        'title': '実績入力済み（保護される）',
        'externalCalendarId': 'calA:evt3',
        'startAtUtc': DateTime(2026, 7, 7).toUtc(),
        'isCompleted': false,
        'actualMinutes': 30,
      });
      await tasksCol.add({
        'title': '別カレンダー（対象外）',
        'externalCalendarId': 'calB:evt4',
        'startAtUtc': DateTime(2026, 7, 7).toUtc(),
        'isCompleted': false,
      });
      await tasksCol.add({
        'title': '再配置済み（保護される）',
        'externalCalendarId': 'calA:evt5',
        'startAtUtc': DateTime(2026, 7, 7).toUtc(),
        'isCompleted': false,
        'repositioned': true,
      });

      await repo.deleteTasksByCalendarInWeek(
        calendarId: 'calA',
        weekStartLocal: weekStart,
      );

      final remaining = await tasksCol.get();
      final remainingTitles = remaining.docs.map((d) => d.data()['title']).toSet();
      expect(remainingTitles, {
        '完了済み（保護される）',
        '実績入力済み（保護される）',
        '別カレンダー（対象外）',
        '再配置済み（保護される）',
      });
    });
  });

  test(
    '既存の宣言済みフラグ・estimatedMinutesは、再同期（toMap null-skip）で巻き戻らない',
    () async {
      await firestore.collection('users').doc(uid).collection('tasks').add({
        'title': '旧タイトル',
        'externalCalendarId': 'cal1:evt1',
        'isTodo': false,
        'predictionDeclared': true,
        'estimatedMinutes': 45,
      });

      // Google側の再取得は常に predictionDeclared: false（未宣言）・estimatedMinutes: null。
      final resynced = CalendarTask(
        id: 'ignored',
        title: '新タイトル',
        start: DateTime(2026, 7, 6, 10),
        end: DateTime(2026, 7, 6, 11),
        rewardYen: 0,
        externalCalendarId: 'cal1:evt1',
      );
      await repo.upsert([resynced]);

      final data = await taskDataByExternalId('cal1:evt1');
      expect(data['title'], '新タイトル');
      expect(data['predictionDeclared'], isTrue,
          reason: '宣言済みフラグはGoogle側の再取得で巻き戻してはいけない');
      expect(data['estimatedMinutes'], 45,
          reason: '宣言済みestimatedMinutesはGoogle側の再取得で巻き戻してはいけない');
    },
  );

  group('createTask', () {
    test('estimatedMinutes省略時は書き込まれず、predictionDeclaredも書かれない', () async {
      await repo.createTask(
        title: '新規予定',
        start: DateTime(2026, 7, 6, 10),
        end: DateTime(2026, 7, 6, 11),
      );

      final snap = await firestore
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .get();
      expect(snap.docs.length, 1);
      final data = snap.docs.first.data();
      expect(data.containsKey('estimatedMinutes'), isFalse);
      expect(data.containsKey('predictionDeclared'), isFalse);
    });

    test('estimatedMinutesとpredictionDeclared:trueを渡すと両方書き込まれる（空きスロット枠＝宣言）', () async {
      await repo.createTask(
        title: '宣言済み予定',
        start: DateTime(2026, 7, 6, 10),
        end: DateTime(2026, 7, 6, 11),
        estimatedMinutes: 60,
        predictionDeclared: true,
      );

      final snap = await firestore
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .get();
      final data = snap.docs.first.data();
      expect(data['estimatedMinutes'], 60);
      expect(data['predictionDeclared'], true);
    });
  });

  group('saveDeclaredPrediction', () {
    test('estimatedMinutesを更新しpredictionDeclaredをtrueにする', () async {
      final doc = await firestore
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .add({'title': 'タスク', 'estimatedMinutes': 30});

      await repo.saveDeclaredPrediction(taskId: doc.id, minutes: 90);

      final data = (await doc.get()).data()!;
      expect(data['estimatedMinutes'], 90);
      expect(data['predictionDeclared'], true);
    });
  });

  group('moveTaskById', () {
    test('start/end を更新し repositioned:true を同一書き込みで立てる', () async {
      final tasksCol =
          firestore.collection('users').doc(uid).collection('tasks');
      final doc = await tasksCol.add({
        'title': 'タスク',
        'startAtUtc': DateTime(2026, 7, 6, 9).toUtc(),
        'endAtUtc': DateTime(2026, 7, 6, 10).toUtc(),
        'isCompleted': false,
      });

      final newStart = DateTime(2026, 7, 6, 13, 15);
      final newEnd = DateTime(2026, 7, 6, 14);
      await repo.moveTaskById(
        taskId: doc.id,
        newStart: newStart,
        newEnd: newEnd,
      );

      final data = (await doc.get()).data()!;
      expect(
        (data['startAtUtc'] as Timestamp)
            .toDate()
            .isAtSameMomentAs(newStart.toUtc()),
        isTrue,
      );
      expect(
        (data['endAtUtc'] as Timestamp)
            .toDate()
            .isAtSameMomentAs(newEnd.toUtc()),
        isTrue,
      );
      expect(data['repositioned'], isTrue);
    });
  });
}
