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

  group('quickPurchaseWish', () {
    test('wishlistへisPurchased=true/purchasedPriceYen=priceのdocを新規作成する', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 1000});

      final result = await repo.quickPurchaseWish(name: 'クイックギフト', price: 300);

      expect(result.applied, isTrue);

      final wishlist = await firestore
          .collection('users')
          .doc(uid)
          .collection('wishlist')
          .where('isPurchased', isEqualTo: true)
          .get();
      expect(wishlist.docs.length, 1);
      final data = wishlist.docs.first.data();
      expect(data['name'], 'クイックギフト');
      expect(data['price'], 300);
      expect(data['purchasedPriceYen'], 300);
      expect(data['createdAt'], isNotNull);
      expect(data['purchasedAt'], isNotNull);
    });

    test('totalEarnedがbefore-priceになる', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 1000});

      final result = await repo.quickPurchaseWish(name: 'クイックギフト', price: 300);

      expect(result.balanceBeforeYen, 1000);
      expect(result.balanceAfterYen, 700);

      final userDoc = await firestore.collection('users').doc(uid).get();
      expect(userDoc.data()?['totalEarned'], 700);
    });

    test('残高不足でもブロックせず適用されafterがマイナスになる', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 100});

      final result = await repo.quickPurchaseWish(name: '高額ギフト', price: 500);

      expect(result.applied, isTrue);
      expect(result.balanceAfterYen, -400);

      final userDoc = await firestore.collection('users').doc(uid).get();
      expect(userDoc.data()?['totalEarned'], -400);
    });

    test('adventure_entriesにwishPurchasedが記録されdeltaYen/sourceIdが正しい', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 1000});

      final result = await repo.quickPurchaseWish(name: 'クイックギフト', price: 300);

      final wishlist = await firestore
          .collection('users')
          .doc(uid)
          .collection('wishlist')
          .where('isPurchased', isEqualTo: true)
          .get();
      final newItemId = wishlist.docs.first.id;

      final entries = await firestore
          .collection('users')
          .doc(uid)
          .collection('adventure_entries')
          .get();
      expect(entries.docs.length, 1);
      final entry = entries.docs.first.data();
      expect(entry['type'], AdventureEntryType.wishPurchased.wireName);
      expect(entry['deltaYen'], -300);
      expect(entry['sourceId'], newItemId);
      expect(result.deltaYen, -300);
    });

    test('daily_earningsを書き込まない', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 1000});

      await repo.quickPurchaseWish(name: 'クイックギフト', price: 300);

      final days = await firestore
          .collection('users')
          .doc(uid)
          .collection('daily_earnings')
          .get();
      expect(days.docs, isEmpty);
    });

    test('price<=0ならno-op（missingAmount）でwishlistに何も作らない', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 1000});

      final result = await repo.quickPurchaseWish(name: '無効な価格', price: 0);

      expect(result.applied, isFalse);
      expect(result.missingAmount, isTrue);

      final wishlist = await firestore
          .collection('users')
          .doc(uid)
          .collection('wishlist')
          .get();
      expect(wishlist.docs, isEmpty);

      final userDoc = await firestore.collection('users').doc(uid).get();
      expect(userDoc.data()?['totalEarned'], 1000);
    });
  });

  group('daily_earnings への日次集計', () {
    String todayKey() {
      final now = DateTime.now();
      String pad2(int v) => v.toString().padLeft(2, '0');
      return '${now.year}-${pad2(now.month)}-${pad2(now.day)}';
    }

    Future<Map<String, dynamic>?> dailyDoc() async {
      final doc = await firestore
          .collection('users')
          .doc(uid)
          .collection('daily_earnings')
          .doc(todayKey())
          .get();
      return doc.data();
    }

    test('adjustBalance(manualAdjusted)はmanualYenへ加算する', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 0});
      await repo.adjustBalance(
        deltaYen: 500,
        type: AdventureEntryType.manualAdjusted,
        title: '手動で受け取り',
      );

      final data = await dailyDoc();
      expect(data?['manualYen'], 500);
      expect(data?['taskYen'], isNull);
      expect(data?['healthYen'], isNull);
    });

    test('completeTaskはtaskYenへ加算する', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 0});
      final ref = await firestore
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .add({'title': 'テストタスク', 'isCompleted': false});

      await repo.completeTask(
        taskId: ref.id,
        title: 'テストタスク',
        rewardYen: 400,
        predictedMinutes: 30,
        actualMinutes: 25,
      );

      final data = await dailyDoc();
      expect(data?['taskYen'], 400);
    });

    test('revertTaskはtaskYenへ相殺分を加算する（マイナス許容）', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 400});
      final ref = await firestore
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .add({
            'title': 'テストタスク',
            'isCompleted': true,
            'completedRewardYen': 400,
          });

      await repo.revertTask(taskId: ref.id, title: 'テストタスク');

      final data = await dailyDoc();
      expect(data?['taskYen'], -400);
    });

    test('saveHealthLogAndAdjustはhealthYenへ加算する', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 0});

      await repo.saveHealthLogAndAdjust(
        dateKey: '2026-07-05',
        healthLogData: {'score': 80},
        deltaYen: 150,
      );

      final data = await dailyDoc();
      expect(data?['healthYen'], 150);
    });

    test('purchaseWishはdaily_earningsを書き込まない', () async {
      await firestore.collection('users').doc(uid).set({'totalEarned': 1000});
      final ref = await firestore
          .collection('users')
          .doc(uid)
          .collection('wishlist')
          .add({'name': 'ギフト', 'price': 500, 'isPurchased': false});

      await repo.purchaseWish(itemId: ref.id, title: 'ギフト');

      final days = await firestore
          .collection('users')
          .doc(uid)
          .collection('daily_earnings')
          .get();
      expect(days.docs, isEmpty);
    });

    test('addWorkSecondsはworkSecondsへincrementする', () async {
      await repo.addWorkSeconds(90);
      await repo.addWorkSeconds(30);

      final data = await dailyDoc();
      expect(data?['workSeconds'], 120);
    });

    test('addWorkSecondsは0以下ならno-op（daily_earningsを作らない）', () async {
      await repo.addWorkSeconds(0);
      await repo.addWorkSeconds(-10);

      final days = await firestore
          .collection('users')
          .doc(uid)
          .collection('daily_earnings')
          .get();
      expect(days.docs, isEmpty);
    });

    test('addWorkSecondsはwhenで指定した日付のdocへ加算する', () async {
      final when = DateTime(2026, 7, 5, 23, 0);
      await repo.addWorkSeconds(60, when: when);

      final doc = await firestore
          .collection('users')
          .doc(uid)
          .collection('daily_earnings')
          .doc('2026-07-05')
          .get();
      expect(doc.data()?['workSeconds'], 60);
    });
  });
}
