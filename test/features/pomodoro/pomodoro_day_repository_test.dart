import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/pomodoro/data/pomodoro_day_repository.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_day.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  const uid = 'test-uid';

  late FakeFirebaseFirestore firestore;
  late DateTime clock;
  late PomodoroDayRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    clock = DateTime(2026, 7, 6, 10, 0, 0); // ローカル想定。
    repo = PomodoroDayRepository(db: firestore, auth: auth, now: () => clock);
  });

  group('docRef', () {
    test('users/{uid}/pomodoro_days/{dateKey} を指す', () {
      final ref = PomodoroDayRepository.docRef(firestore, uid, '2026-07-06');
      expect(ref.path, 'users/$uid/pomodoro_days/2026-07-06');
    });
  });

  group('readToday', () {
    test('doc が無ければ null を返す', () async {
      final result = await repo.readToday();
      expect(result, isNull);
    });

    test('doc があれば今日（ローカル日付）のdocを読む', () async {
      await PomodoroDayRepository.docRef(firestore, uid, '2026-07-06').set(
        PomodoroDay(
          completedSetsToday: 3,
          cycleCompletedSets: 1,
          updatedAtUtc: clock.toUtc(),
        ).toMap(),
      );

      final result = await repo.readToday();
      expect(result, isNotNull);
      expect(result!.completedSetsToday, 3);
      expect(result.cycleCompletedSets, 1);
    });
  });

  group('watch', () {
    test('doc が無ければ null を流す', () async {
      final stream = repo.watch('2026-07-06');
      final first = await stream.first;
      expect(first, isNull);
    });

    test('書き込み後は最新値を流す', () async {
      final ref = PomodoroDayRepository.docRef(firestore, uid, '2026-07-06');
      final stream = repo.watch('2026-07-06');
      final values = <PomodoroDay?>[];
      final sub = stream.listen(values.add);
      await Future<void>.delayed(Duration.zero);

      await ref.set(
        PomodoroDay(
          completedSetsToday: 5,
          cycleCompletedSets: 2,
          updatedAtUtc: clock.toUtc(),
        ).toMap(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(values.last, isNotNull);
      expect(values.last!.completedSetsToday, 5);
      await sub.cancel();
    });
  });

  group('未認証', () {
    test('readTodayはnullを返す', () async {
      final unauth = _MockFirebaseAuth();
      when(() => unauth.currentUser).thenReturn(null);
      final unauthRepo = PomodoroDayRepository(db: firestore, auth: unauth);
      expect(await unauthRepo.readToday(), isNull);
    });

    test('watchはnullを流す', () async {
      final unauth = _MockFirebaseAuth();
      when(() => unauth.currentUser).thenReturn(null);
      final unauthRepo = PomodoroDayRepository(db: firestore, auth: unauth);
      expect(await unauthRepo.watch('2026-07-06').first, isNull);
    });
  });
}
