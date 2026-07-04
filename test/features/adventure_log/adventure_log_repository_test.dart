import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/adventure_log/data/adventure_log_repository.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  const uid = 'test-uid';
  const backfillMarkerKey = 'adventureEntriesBackfillV1CompletedAtUtc';

  late FakeFirebaseFirestore firestore;
  late AdventureLogRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    repo = AdventureLogRepository(db: firestore, auth: auth);
  });

  group('watchEntries', () {
    test('backfill未完了の場合はlegacyのtasks/wishlistも取り込む', () async {
      await firestore.collection('users').doc(uid).collection('tasks').add({
        'title': '旧タスク',
        'isCompleted': true,
        'completedAtUtc': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'startAtUtc': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'endAtUtc': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'reward': 500,
      });

      List<dynamic>? latest;
      final sub = repo.watchEntries().listen((entries) => latest = entries);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(latest, isNotNull);
      expect(latest!.length, 1);
    });

    test('backfill完了済みならlegacyのtasks/wishlistコレクションを購読しない', () async {
      await firestore.collection('users').doc(uid).set({
        backfillMarkerKey: Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      // adventure_entries には既に移行済みの1件のみ存在する想定。
      await firestore
          .collection('users')
          .doc(uid)
          .collection('adventure_entries')
          .add({
            'type': 'taskCompleted',
            'title': '移行済みタスク',
            'deltaYen': 500,
            'balanceBeforeYen': 0,
            'balanceAfterYen': 500,
            'occurredAtUtc': Timestamp.fromDate(DateTime(2026, 1, 1)),
            'createdAtUtc': Timestamp.fromDate(DateTime(2026, 1, 1)),
          });
      // legacy 側にも（本来ありえないが）データが残っていたとしても無視されるべき。
      await firestore.collection('users').doc(uid).collection('tasks').add({
        'title': '未移行のはずの旧タスク',
        'isCompleted': true,
        'completedAtUtc': Timestamp.fromDate(DateTime(2026, 1, 2)),
        'startAtUtc': Timestamp.fromDate(DateTime(2026, 1, 2)),
        'endAtUtc': Timestamp.fromDate(DateTime(2026, 1, 2)),
        'reward': 300,
      });

      List<dynamic>? latest;
      final sub = repo.watchEntries().listen((entries) => latest = entries);
      addTearDown(sub.cancel);
      // userRef.get() による backfill 判定（非同期）が解決するのを待つ。
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(latest, isNotNull);
      expect(latest!.length, 1);
      expect((latest!.first as dynamic).title, '移行済みタスク');
    });
  });
}
