import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/economy/data/economy_repository.dart';
import 'package:task_manager/features/economy/providers/economy_providers.dart';
import 'package:task_manager/features/wish_list/model/wish_item.dart';

class WishListViewModel extends Notifier<AsyncValue<List<WishItem>>> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  String? get _uid => _auth.currentUser?.uid;

  @override
  AsyncValue<List<WishItem>> build() {
    // ログイン状態（uid）の変化を購読し、サインイン直後に再ビルド→再購読する。
    final uid = ref.watch(
      authStateProvider.select((async) => async.asData?.value?.uid),
    );
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    if (uid == null) {
      return const AsyncValue.data([]);
    }
    Future.microtask(() => _subscribe(uid));
    return const AsyncValue.loading();
  }

  void _subscribe(String uid) {
    _sub?.cancel();
    _sub = _db
        .collection('users')
        .doc(uid)
        .collection('wishlist')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      (snapshot) {
        state = AsyncValue.data(
          snapshot.docs.map(WishItem.fromFirestore).toList(),
        );
      },
      onError: (e) => state = AsyncValue.error(e, StackTrace.current),
    );
  }

  Future<String?> uploadWishImage(File file) async {
    final uid = _uid;
    if (uid == null) return null;
    final name = DateTime.now().millisecondsSinceEpoch.toString();
    final ref = _storage.ref('wishlist/$uid/$name.jpg');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  Future<void> addItem({
    required String name,
    required int price,
    String shopUrl = '',
    String imageUrl = '',
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final item = WishItem(
      id: '',
      name: name,
      price: price,
      shopUrl: shopUrl,
      imageUrl: imageUrl,
      createdAt: DateTime.now(),
    );
    await _db
        .collection('users')
        .doc(uid)
        .collection('wishlist')
        .add(item.toFirestore());
  }

  /// 戻り値: transaction の適用結果。残高不足などは result flags で返す。
  Future<BalanceLedgerResult> togglePurchased(WishItem item) async {
    final uid = _uid;
    if (uid == null) {
      return const BalanceLedgerResult(
        applied: false,
        deltaYen: 0,
        balanceBeforeYen: 0,
        balanceAfterYen: 0,
      );
    }

    final newPurchased = !item.isPurchased;
    final economy = ref.read(economyRepositoryProvider);
    final result = newPurchased
        ? await economy.purchaseWish(itemId: item.id, title: item.name)
        : await economy.unpurchaseWish(itemId: item.id, title: item.name);
    return result;
  }

  Future<void> deleteItem(String itemId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('wishlist')
        .doc(itemId)
        .delete();
  }
}

final wishListProvider =
    NotifierProvider<WishListViewModel, AsyncValue<List<WishItem>>>(
  WishListViewModel.new,
);
