import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/adventure_log/model/adventure_log_entry.dart';
import 'package:task_manager/features/economy/data/economy_repository.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  const uid = 'test-uid';

  late FakeFirebaseFirestore firestore;
  late EconomyRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    repo = EconomyRepository(db: firestore, auth: auth);
  });

  group('adjustBalance', () {
    test('残高を加算しadventure_entriesに1件記録する', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 1000});

      final result = await repo.adjustBalance(
        deltaYen: 500,
        type: AdventureEntryType.manualAdjusted,
        title: '手動で受け取り',
      );

      expect(result.applied, isTrue);
      expect(result.balanceBeforeYen, 1000);
      expect(result.balanceAfterYen, 1500);

      final userDoc = await firestore.collection('users').doc(uid).get();
      expect(userDoc.data()?['totalEarned'], 1500);

      final entries = await firestore
          .collection('users')
          .doc(uid)
          .collection('adventure_entries')
          .get();
      expect(entries.docs.length, 1);
      expect(entries.docs.first.data()['deltaYen'], 500);
    });

    test('deltaYenが0ならFirestoreに書き込まずapplied=falseを返す', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 1000});

      final result = await repo.adjustBalance(
        deltaYen: 0,
        type: AdventureEntryType.manualAdjusted,
        title: '手動で受け取り',
      );

      expect(result.applied, isFalse);
      expect(result.balanceBeforeYen, 1000);
      expect(result.balanceAfterYen, 1000);

      final entries = await firestore
          .collection('users')
          .doc(uid)
          .collection('adventure_entries')
          .get();
      expect(entries.docs, isEmpty);
    });
  });

  group('completeTask', () {
    Future<String> addTask() async {
      final ref = await firestore
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .add({'title': 'テストタスク', 'isCompleted': false});
      return ref.id;
    }

    test('残高・累計タスク数を更新しタスクをisCompleted=trueにする', () async {
      await firestore.collection('users').doc(uid).set({
        'totalEarned': 1000,
        'cumulativeTaskCount': 3,
      });
      final taskId = await addTask();

      final result = await repo.completeTask(
        taskId: taskId,
        title: 'テストタスク',
        rewardYen: 300,
        predictedMinutes: 30,
        actualMinutes: 25,
      );

      expect(result.applied, isTrue);
      expect(result.balanceAfterYen, 1300);
      expect(result.cumulativeTaskCountAfter, 4);

      final taskDoc = await firestore
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc(taskId)
          .get();
      expect(taskDoc.data()?['isCompleted'], isTrue);
      expect(taskDoc.data()?['actualMinutes'], 25);
    });

    test('既に完了済みのタスクは再付与せずapplied=falseを返す（二重付与防止）', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 1000});
      final ref = await firestore
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .add({'title': 'テストタスク', 'isCompleted': true});

      final result = await repo.completeTask(
        taskId: ref.id,
        title: 'テストタスク',
        rewardYen: 300,
        predictedMinutes: 30,
        actualMinutes: 25,
      );

      expect(result.applied, isFalse);
      expect(result.balanceAfterYen, 1000);

      final userDoc = await firestore.collection('users').doc(uid).get();
      expect(userDoc.data()?['totalEarned'], 1000);
    });
  });

  group('saveHealthLogAndAdjust', () {
    test('entryTitleを指定するとadventure_entriesのtitleに反映される', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 1000});

      await repo.saveHealthLogAndAdjust(
        dateKey: '2026-07-05',
        healthLogData: {'dateKey': '2026-07-05'},
        deltaYen: 300,
        entryTitle: '運動 +30 分',
      );

      final entries = await firestore
          .collection('users')
          .doc(uid)
          .collection('adventure_entries')
          .get();
      expect(entries.docs.length, 1);
      expect(entries.docs.first.data()['title'], '運動 +30 分');
    });

    test('entryTitleがnullまたは空文字なら健康スコアにフォールバックする', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 1000});

      await repo.saveHealthLogAndAdjust(
        dateKey: '2026-07-05',
        healthLogData: {'dateKey': '2026-07-05'},
        deltaYen: 300,
      );
      await repo.saveHealthLogAndAdjust(
        dateKey: '2026-07-05',
        healthLogData: {'dateKey': '2026-07-05'},
        deltaYen: 300,
        entryTitle: '',
      );

      final entries = await firestore
          .collection('users')
          .doc(uid)
          .collection('adventure_entries')
          .get();
      expect(entries.docs.length, 2);
      expect(
        entries.docs.map((d) => d.data()['title']),
        everyElement('健康スコア'),
      );
    });

    test('deltaYenが0ならentryTitleを渡してもエントリを作成しない', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 1000});

      await repo.saveHealthLogAndAdjust(
        dateKey: '2026-07-05',
        healthLogData: {'dateKey': '2026-07-05'},
        deltaYen: 0,
        entryTitle: '運動 +30 分',
      );

      final entries = await firestore
          .collection('users')
          .doc(uid)
          .collection('adventure_entries')
          .get();
      expect(entries.docs, isEmpty);
    });
  });
}
