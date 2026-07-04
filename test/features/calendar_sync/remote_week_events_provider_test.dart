import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/core/providers/firebase_providers.dart';
import 'package:task_manager/features/calendar_sync/data/google_calendar_repository.dart';
import 'package:task_manager/features/calendar_sync/model/google_account_info.dart';
import 'package:task_manager/features/calendar_sync/model/google_calendar_source.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/models/calendar_task.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _FakeGoogleCalendarRepository implements GoogleCalendarRepository {
  final fetchCallCounts = <String, int>{};

  @override
  Future<List<CalendarTask>> fetchWeekEvents({
    required String calendarId,
    required DateTime weekStartLocal,
    String? accountId,
  }) async {
    final key = '$calendarId@$weekStartLocal';
    fetchCallCounts[key] = (fetchCallCounts[key] ?? 0) + 1;
    return const [];
  }

  @override
  Future<GoogleAccountInfo?> getCurrentAccount() async => null;

  @override
  Future<List<GoogleCalendarSource>> fetchCalendars() async => const [];

  @override
  Future<GoogleAccountInfo?> signInWithPicker() async => null;
}

void main() {
  test(
    '可視設定のトグルは再フィルタのみで完結し、既にフェッチ済みのカレンダーは再フェッチしない',
    () async {
      const uid = 'test-uid';
      final firestore = FakeFirebaseFirestore();
      final auth = _MockFirebaseAuth();
      final user = _MockUser();
      when(() => user.uid).thenReturn(uid);
      when(() => auth.currentUser).thenReturn(user);
      final fakeRepo = _FakeGoogleCalendarRepository();

      final container = ProviderContainer(overrides: [
        firebaseFirestoreProvider.overrideWithValue(firestore),
        firebaseAuthProvider.overrideWithValue(auth),
        googleCalendarRepositoryProvider.overrideWithValue(fakeRepo),
      ]);
      addTearDown(container.dispose);

      const account = GoogleAccountInfo(id: 'acc1', email: 'a@example.com');
      container.read(currentGoogleAccountProvider.notifier).set(account);

      // build() の初回ロード完了を待ってから操作する（setVisible との競合を避ける）。
      await container.read(calendarVisibilityProvider.future);

      final weekStart = DateTime(2026, 7, 6);

      // カレンダーA・Bを両方可視にする。
      await container
          .read(calendarVisibilityProvider.notifier)
          .setVisible(accountId: 'acc1', calendarId: 'calA', visible: true);
      await container
          .read(calendarVisibilityProvider.notifier)
          .setVisible(accountId: 'acc1', calendarId: 'calB', visible: true);

      container.listen(remoteWeekEventsProvider(weekStart), (_, _) {});
      await container.read(remoteWeekEventsProvider(weekStart).future);

      expect(fakeRepo.fetchCallCounts['calA@$weekStart'], 1);
      expect(fakeRepo.fetchCallCounts['calB@$weekStart'], 1);

      // カレンダーAだけ非表示→再表示。
      await container
          .read(calendarVisibilityProvider.notifier)
          .setVisible(accountId: 'acc1', calendarId: 'calA', visible: false);
      await container.read(remoteWeekEventsProvider(weekStart).future);

      await container
          .read(calendarVisibilityProvider.notifier)
          .setVisible(accountId: 'acc1', calendarId: 'calA', visible: true);
      await container.read(remoteWeekEventsProvider(weekStart).future);

      // 既にフェッチ済みなのでネットワーク呼び出しは増えない。
      expect(fakeRepo.fetchCallCounts['calA@$weekStart'], 1);
      // Aのトグルによって無関係なBが再フェッチされてもいけない。
      expect(fakeRepo.fetchCallCounts['calB@$weekStart'], 1);
    },
  );
}
