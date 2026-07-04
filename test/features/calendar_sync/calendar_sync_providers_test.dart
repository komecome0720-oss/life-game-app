import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  const uid = 'test-uid';

  late FakeFirebaseFirestore firestore;
  late ProviderContainer container;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);

    container = ProviderContainer(overrides: [
      firebaseFirestoreProvider.overrideWithValue(firestore),
      firebaseAuthProvider.overrideWithValue(auth),
    ]);
    addTearDown(container.dispose);
  });

  group('CalendarVisibilityNotifier.setVisible', () {
    test('書き込み失敗時は state を更新前の値に戻し false を返す', () async {
      await container.read(calendarVisibilityProvider.future);

      final ok1 = await container
          .read(calendarVisibilityProvider.notifier)
          .setVisible(accountId: 'acc1', calendarId: 'cal1', visible: true);
      expect(ok1, isTrue);
      final afterSuccess = container.read(calendarVisibilityProvider).value;
      expect(afterSuccess?['acc1'], {'cal1'});

      final docRef = firestore
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('calendarVisibility');
      whenCalling(Invocation.method(#set, null))
          .on(docRef)
          .thenThrow(Exception('offline'));

      final ok2 = await container
          .read(calendarVisibilityProvider.notifier)
          .setVisible(accountId: 'acc1', calendarId: 'cal2', visible: true);

      expect(ok2, isFalse);
      final afterFailure = container.read(calendarVisibilityProvider).value;
      expect(afterFailure?['acc1'], {'cal1'},
          reason: '書き込み失敗時は更新前の状態にロールバックされているべき');
    });
  });

  group('CalendarDownloadNotifier.setDownloaded', () {
    test('書き込み失敗時は state を更新前の値に戻し false を返す', () async {
      await container.read(calendarDownloadProvider.future);

      final ok1 = await container
          .read(calendarDownloadProvider.notifier)
          .setDownloaded(accountId: 'acc1', calendarId: 'cal1', downloaded: true);
      expect(ok1, isTrue);

      final docRef = firestore
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('calendarDownload');
      whenCalling(Invocation.method(#set, null))
          .on(docRef)
          .thenThrow(Exception('offline'));

      final ok2 = await container
          .read(calendarDownloadProvider.notifier)
          .setDownloaded(accountId: 'acc1', calendarId: 'cal1', downloaded: false);

      expect(ok2, isFalse);
      final afterFailure = container.read(calendarDownloadProvider).value;
      expect(afterFailure?['acc1'], {'cal1'},
          reason: '書き込み失敗時は更新前の状態（DL=trueのまま）にロールバックされているべき');
    });
  });

  group('CalendarQuadrantNotifier.setQuadrant', () {
    test('書き込み失敗時は state を更新前の値に戻し false を返す', () async {
      await container.read(calendarQuadrantProvider.future);

      final ok1 = await container
          .read(calendarQuadrantProvider.notifier)
          .setQuadrant(accountId: 'acc1', calendarId: 'cal1', quadrantNumber: 2);
      expect(ok1, isTrue);

      final docRef = firestore
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('calendarQuadrant');
      whenCalling(Invocation.method(#set, null))
          .on(docRef)
          .thenThrow(Exception('offline'));

      final ok2 = await container
          .read(calendarQuadrantProvider.notifier)
          .setQuadrant(accountId: 'acc1', calendarId: 'cal1', quadrantNumber: 3);

      expect(ok2, isFalse);
      final afterFailure = container.read(calendarQuadrantProvider).value;
      expect(afterFailure?['acc1']?['cal1'], 2,
          reason: '書き込み失敗時は更新前の象限（2）にロールバックされているべき');
    });
  });
}
