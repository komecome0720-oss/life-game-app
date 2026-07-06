import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/timer/data/active_timer_repository.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  const uid = 'test-uid';

  late FakeFirebaseFirestore firestore;
  late DateTime clock;
  late ActiveTimerRepository repo;

  Future<Map<String, dynamic>?> rawDoc() async {
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('active_timer')
        .doc('current')
        .get();
    return snap.data();
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    clock = DateTime.utc(2026, 7, 6, 10, 0, 0);
    repo = ActiveTimerRepository(db: firestore, auth: auth, now: () => clock);
  });

  group('start', () {
    test('未存在なら新規作成し、startedAtUtc=now・accumulatedSeconds=0で返す', () async {
      final timer = await repo.start(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
      );

      expect(timer.taskId, 'task-1');
      expect(timer.isRunning, isTrue);
      expect(timer.startedAtUtc, clock);
      expect(timer.accumulatedSeconds, 0);

      final data = await rawDoc();
      expect(data, isNotNull);
      expect(data!['taskId'], 'task-1');
    });

    test('既存ドキュメントがあれば上書きせずそれを返す', () async {
      await repo.start(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
      );

      clock = clock.add(const Duration(minutes: 5));
      final second = await repo.start(
        taskId: 'task-2', // 別タスクで開始しようとしても既存を返す
        isTodo: true,
        taskTitle: '別タスク',
        predictedMinutes: 30,
      );

      expect(second.taskId, 'task-1');
      expect(second.predictedMinutes, 60);
    });
  });

  group('startLocalFirst', () {
    test('timerを即時返し、write完了後にdocが存在する', () async {
      final started = repo.startLocalFirst(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
      );

      expect(started.timer.taskId, 'task-1');
      expect(started.timer.isRunning, isTrue);
      expect(started.timer.startedAtUtc, clock);
      expect(started.timer.accumulatedSeconds, 0);

      await started.write;
      final data = await rawDoc();
      expect(data, isNotNull);
      expect(data!['taskId'], 'task-1');
    });

    test('未認証なら同期的にthrowする', () {
      final auth = _MockFirebaseAuth();
      when(() => auth.currentUser).thenReturn(null);
      final unauthRepo =
          ActiveTimerRepository(db: firestore, auth: auth, now: () => clock);

      expect(
        () => unauthRepo.startLocalFirst(
          taskId: 'task-1',
          isTodo: false,
          taskTitle: 'サンプル',
          predictedMinutes: 60,
        ),
        throwsException,
      );
    });
  });

  group('pause / resume', () {
    test('pauseで経過秒数がaccumulatedSecondsへ加算されstartedAtUtcがnullになる', () async {
      final started = await repo.start(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
      );

      clock = clock.add(const Duration(seconds: 90));
      await repo.pause(started);

      final data = await rawDoc();
      expect(data!['accumulatedSeconds'], 90);
      expect(data['startedAtUtc'], isNull);
    });

    test('pause -> resume -> pause で経過が積み上がる', () async {
      final started = await repo.start(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
      );

      clock = clock.add(const Duration(seconds: 60));
      await repo.pause(started);
      var data = await rawDoc();
      expect(data!['accumulatedSeconds'], 60);

      // resume: startedAtUtc が現在時刻に更新される
      final paused = started.copyWith(
        clearStartedAt: true,
        accumulatedSeconds: 60,
      );
      await repo.resume(paused);
      data = await rawDoc();
      expect(data!['startedAtUtc'], isNotNull);

      clock = clock.add(const Duration(seconds: 30));
      final resumed = paused.copyWith(
        startedAtUtc: (data['startedAtUtc'] as dynamic).toDate(),
      );
      await repo.pause(resumed);
      data = await rawDoc();
      expect(data!['accumulatedSeconds'], 90);
    });
  });

  group('resetToZero', () {
    test('accumulatedSeconds=0・startedAtUtc=nullにする', () async {
      final started = await repo.start(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
      );
      clock = clock.add(const Duration(seconds: 45));
      await repo.pause(started);

      await repo.resetToZero();
      final data = await rawDoc();
      expect(data!['accumulatedSeconds'], 0);
      expect(data['startedAtUtc'], isNull);
    });
  });

  group('clear', () {
    test('ドキュメントを削除する', () async {
      await repo.start(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
      );
      await repo.clear();
      final data = await rawDoc();
      expect(data, isNull);
    });
  });

  group('watch', () {
    test('存在しない場合は null を流す', () async {
      final value = await repo.watch().first;
      expect(value, isNull);
    });

    test('作成後は ActiveTimer を流す', () async {
      await repo.start(
        taskId: 'task-1',
        isTodo: false,
        taskTitle: 'サンプル',
        predictedMinutes: 60,
      );
      final value = await repo.watch().first;
      expect(value, isNotNull);
      expect(value!.taskId, 'task-1');
    });
  });
}
