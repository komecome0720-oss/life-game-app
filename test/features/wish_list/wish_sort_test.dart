import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/wish_list/model/wish_item.dart';
import 'package:task_manager/features/wish_list/model/wish_sort.dart';
import 'package:task_manager/features/wish_list/viewmodel/wish_sort_providers.dart';

void main() {
  WishItem item({
    required String id,
    int price = 0,
    required DateTime createdAt,
    DateTime? purchasedAt,
  }) {
    return WishItem(
      id: id,
      name: id,
      price: price,
      createdAt: createdAt,
      purchasedAt: purchasedAt,
      isPurchased: purchasedAt != null,
    );
  }

  group('sortWishItems', () {
    test('金額 昇順：同額はタイブレークで追加日降順になる', () {
      final items = [
        item(id: 'a', price: 300, createdAt: DateTime(2024, 1, 1)),
        item(id: 'b', price: 100, createdAt: DateTime(2024, 1, 2)),
        item(id: 'c', price: 100, createdAt: DateTime(2024, 1, 3)),
      ];
      final sorted = sortWishItems(
        items,
        const WishSort(key: WishSortKey.price, descending: false),
      );
      // price 100 同士は createdAt 降順 → c(1/3) が b(1/2) より先。
      expect(sorted.map((e) => e.id).toList(), ['c', 'b', 'a']);
    });

    test('金額 降順', () {
      final items = [
        item(id: 'a', price: 300, createdAt: DateTime(2024, 1, 1)),
        item(id: 'b', price: 100, createdAt: DateTime(2024, 1, 2)),
        item(id: 'c', price: 200, createdAt: DateTime(2024, 1, 3)),
      ];
      final sorted = sortWishItems(
        items,
        const WishSort(key: WishSortKey.price, descending: true),
      );
      expect(sorted.map((e) => e.id).toList(), ['a', 'c', 'b']);
    });

    test('追加日 昇順', () {
      final items = [
        item(id: 'a', createdAt: DateTime(2024, 1, 3)),
        item(id: 'b', createdAt: DateTime(2024, 1, 1)),
        item(id: 'c', createdAt: DateTime(2024, 1, 2)),
      ];
      final sorted = sortWishItems(
        items,
        const WishSort(key: WishSortKey.createdAt, descending: false),
      );
      expect(sorted.map((e) => e.id).toList(), ['b', 'c', 'a']);
    });

    test('追加日 降順', () {
      final items = [
        item(id: 'a', createdAt: DateTime(2024, 1, 3)),
        item(id: 'b', createdAt: DateTime(2024, 1, 1)),
        item(id: 'c', createdAt: DateTime(2024, 1, 2)),
      ];
      final sorted = sortWishItems(
        items,
        const WishSort(key: WishSortKey.createdAt, descending: true),
      );
      expect(sorted.map((e) => e.id).toList(), ['a', 'c', 'b']);
    });

    test('獲得日 昇順：purchasedAt null は末尾に来る', () {
      final items = [
        item(
          id: 'a',
          createdAt: DateTime(2024, 1, 1),
          purchasedAt: DateTime(2024, 2, 3),
        ),
        item(id: 'b', createdAt: DateTime(2024, 1, 2)), // purchasedAt null
        item(
          id: 'c',
          createdAt: DateTime(2024, 1, 3),
          purchasedAt: DateTime(2024, 2, 1),
        ),
      ];
      final sorted = sortWishItems(
        items,
        const WishSort(key: WishSortKey.purchasedAt, descending: false),
      );
      expect(sorted.map((e) => e.id).toList(), ['c', 'a', 'b']);
    });

    test('獲得日 降順：purchasedAt null は末尾に来る', () {
      final items = [
        item(
          id: 'a',
          createdAt: DateTime(2024, 1, 1),
          purchasedAt: DateTime(2024, 2, 3),
        ),
        item(id: 'b', createdAt: DateTime(2024, 1, 2)), // purchasedAt null
        item(
          id: 'c',
          createdAt: DateTime(2024, 1, 3),
          purchasedAt: DateTime(2024, 2, 1),
        ),
      ];
      final sorted = sortWishItems(
        items,
        const WishSort(key: WishSortKey.purchasedAt, descending: true),
      );
      expect(sorted.map((e) => e.id).toList(), ['a', 'c', 'b']);
    });

    test('元リストは非破壊', () {
      final items = [
        item(id: 'a', price: 300, createdAt: DateTime(2024, 1, 1)),
        item(id: 'b', price: 100, createdAt: DateTime(2024, 1, 2)),
      ];
      final original = [...items];
      sortWishItems(
        items,
        const WishSort(key: WishSortKey.price, descending: false),
      );
      expect(items.map((e) => e.id).toList(), original.map((e) => e.id).toList());
    });
  });

  group('WishSortNotifier', () {
    test('setKey は方向を維持、toggleDirection は反転する', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(activeWishSortProvider),
        const WishSort(key: WishSortKey.createdAt, descending: true),
      );

      container.read(activeWishSortProvider.notifier).setKey(WishSortKey.price);
      expect(
        container.read(activeWishSortProvider),
        const WishSort(key: WishSortKey.price, descending: true),
      );

      container.read(activeWishSortProvider.notifier).toggleDirection();
      expect(
        container.read(activeWishSortProvider),
        const WishSort(key: WishSortKey.price, descending: false),
      );
    });

    test('purchasedWishSortProvider の初期値は獲得日・降順', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(purchasedWishSortProvider),
        const WishSort(key: WishSortKey.purchasedAt, descending: true),
      );
    });
  });
}
