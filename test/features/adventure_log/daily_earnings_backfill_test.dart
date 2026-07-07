import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/adventure_log/data/daily_earnings_backfill.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  const uid = 'test-uid';

  late FakeFirebaseFirestore firestore;
  late DailyEarningsBackfill backfill;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    backfill = DailyEarningsBackfill(db: firestore, auth: auth);
  });

  Future<void> addEntry({
    required String type,
    required int deltaYen,
    required DateTime occurredAt,
  }) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('adventure_entries')
        .add({
          'type': type,
          'title': 'テスト',
          'deltaYen': deltaYen,
          'occurredAtUtc': Timestamp.fromDate(occurredAt.toUtc()),
          'createdAtUtc': Timestamp.fromDate(occurredAt.toUtc()),
        });
  }

  test('タイプ別に日次集計し、wish系は除外する', () async {
    final day = DateTime(2026, 7, 5, 9);
    await addEntry(type: 'taskCompleted', deltaYen: 500, occurredAt: day);
    await addEntry(
      type: 'taskReverted',
      deltaYen: -200,
      occurredAt: day.add(const Duration(hours: 1)),
    );
    await addEntry(type: 'healthAdjusted', deltaYen: 100, occurredAt: day);
    await addEntry(type: 'manualAdjusted', deltaYen: 50, occurredAt: day);
    await addEntry(
      type: 'wishPurchased',
      deltaYen: -800,
      occurredAt: day,
    );

    await backfill.backfillIfNeeded();

    final dayDoc = await firestore
        .collection('users')
        .doc(uid)
        .collection('daily_earnings')
        .doc('2026-07-05')
        .get();
    expect(dayDoc.data()?['taskYen'], 300);
    expect(dayDoc.data()?['healthYen'], 100);
    expect(dayDoc.data()?['manualYen'], 50);

    final userDoc = await firestore.collection('users').doc(uid).get();
    expect(
      userDoc.data()?['dailyEarningsBackfillV1CompletedAtUtc'],
      isNotNull,
    );
  });

  test('既にマーカーがある場合は何もしない', () async {
    await firestore.collection('users').doc(uid).set({
      'dailyEarningsBackfillV1CompletedAtUtc': Timestamp.now(),
    });
    await addEntry(
      type: 'taskCompleted',
      deltaYen: 500,
      occurredAt: DateTime(2026, 7, 5),
    );

    await backfill.backfillIfNeeded();

    final days = await firestore
        .collection('users')
        .doc(uid)
        .collection('daily_earnings')
        .get();
    expect(days.docs, isEmpty);
  });
}
