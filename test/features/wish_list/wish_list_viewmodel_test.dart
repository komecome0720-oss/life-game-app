import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/core/providers/firebase_providers.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/wish_list/viewmodel/wish_list_viewmodel.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  test(
    'ユーザー切り替え中に旧購読のイベントが遅れて届いても、'
    '前ユーザーのデータで state を上書きしない',
    () async {
      final firestore = FakeFirebaseFirestore();
      final auth = _MockFirebaseAuth();
      final userA = _MockUser();
      final userB = _MockUser();
      when(() => userA.uid).thenReturn('userA');
      when(() => userB.uid).thenReturn('userB');
      // 購読開始時点では userA としてログイン中。
      when(() => auth.currentUser).thenReturn(userA);

      final container = ProviderContainer(overrides: [
        firebaseFirestoreProvider.overrideWithValue(firestore),
        firebaseAuthProvider.overrideWithValue(auth),
        authStateProvider.overrideWith((ref) => Stream.value(userA)),
      ]);
      addTearDown(container.dispose);

      // userA のドキュメントを1件用意し、購読させる。
      await firestore
          .collection('users')
          .doc('userA')
          .collection('wishlist')
          .add({'name': '旧ユーザーの欲しいもの', 'price': 1000, 'createdAt': DateTime.now()});

      container.listen(wishListProvider, (_, _) {});
      // build() 内の Future.microtask(() => _subscribe(uid)) が実行されるのを待つ。
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final beforeSwitch = container.read(wishListProvider).value;
      expect(beforeSwitch, isNotNull);
      expect(beforeSwitch!.length, 1);

      // 実際のログインは既に userB に切り替わっているが、
      // userA 向けの古い StreamSubscription はまだキャンセルされていない状況を再現する。
      when(() => auth.currentUser).thenReturn(userB);

      // 旧購読（userA のコレクション）に新規イベントを発生させる。
      await firestore
          .collection('users')
          .doc('userA')
          .collection('wishlist')
          .add({'name': '旧ユーザーの追加アイテム', 'price': 500, 'createdAt': DateTime.now()});
      await Future<void>.delayed(Duration.zero);

      final afterStaleEvent = container.read(wishListProvider).value;
      expect(afterStaleEvent, equals(beforeSwitch),
          reason: '現在のログインユーザーが userB に変わった後は、'
              'userA 向けの古い購読イベントで state を書き換えてはいけない');
    },
  );
}
