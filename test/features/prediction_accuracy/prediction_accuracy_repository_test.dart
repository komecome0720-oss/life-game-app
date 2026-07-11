import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/prediction_accuracy/data/prediction_accuracy_repository.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  const uid = 'test-uid';

  late FakeFirebaseFirestore firestore;
  late PredictionAccuracyRepository repo;

  Future<void> addTask(
    String id, {
    required bool predictionDeclared,
    required int predictedMinutes,
    required int actualMinutes,
    DateTime? completedAt,
  }) async {
    await firestore.collection('users').doc(uid).collection('tasks').doc(id).set({
      'title': id,
      'isCompleted': true,
      if (predictionDeclared) 'predictionDeclared': true,
      'predictedMinutes': predictedMinutes,
      'actualMinutes': actualMinutes,
      if (completedAt != null)
        'completedAtUtc': Timestamp.fromDate(completedAt.toUtc()),
    });
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    repo = PredictionAccuracyRepository(db: firestore, auth: auth);
  });

  group('watchStats', () {
    test('predictionDeclared=falseの完了タスクは統計から除外される（シーズン2リセット）',
        () async {
      await addTask(
        'declared-1',
        predictionDeclared: true,
        predictedMinutes: 30,
        actualMinutes: 30,
      );
      await addTask(
        'legacy-1',
        predictionDeclared: false,
        predictedMinutes: 30,
        actualMinutes: 60,
      );

      final stats = await repo.watchStats().first;
      expect(stats.cumulativeCount, 1);
      expect(stats.averageError, closeTo(0.0, 1e-9));
    });

    test('宣言済みでも実績が未記録なら除外される', () async {
      await addTask(
        'declared-no-actual',
        predictionDeclared: true,
        predictedMinutes: 30,
        actualMinutes: 0,
      );

      final stats = await repo.watchStats().first;
      expect(stats.cumulativeCount, 0);
      expect(stats.averageError, isNull);
    });

    test('windowCountは対象件数が30未満ならそのまま、30以上なら30に丸める', () async {
      for (var i = 0; i < 5; i++) {
        await addTask(
          'declared-$i',
          predictionDeclared: true,
          predictedMinutes: 30,
          actualMinutes: 30,
          completedAt: DateTime.utc(2026, 7, 1 + i),
        );
      }

      final stats = await repo.watchStats().first;
      expect(stats.windowCount, 5);
      expect(stats.cumulativeCount, 5);
    });
  });
}
