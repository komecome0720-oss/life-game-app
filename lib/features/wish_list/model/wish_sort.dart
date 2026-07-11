import 'package:task_manager/features/wish_list/model/wish_item.dart';

/// 欲しいものリストの並び替え基準。
enum WishSortKey { createdAt, price, purchasedAt }

extension WishSortKeyX on WishSortKey {
  String get label => switch (this) {
    WishSortKey.createdAt => '追加日',
    WishSortKey.price => '金額',
    WishSortKey.purchasedAt => '獲得日',
  };
}

/// 未獲得タブで選択可能な並び替え基準。
const kActiveWishSortKeys = [WishSortKey.createdAt, WishSortKey.price];

/// 獲得済みタブで選択可能な並び替え基準。
const kPurchasedWishSortKeys = [
  WishSortKey.createdAt,
  WishSortKey.price,
  WishSortKey.purchasedAt,
];

/// 並び替え条件（基準＋方向）。その場限りの状態としてメモリ保持のみ行う（永続化しない）。
class WishSort {
  const WishSort({required this.key, required this.descending});

  final WishSortKey key;

  /// true なら降順、false なら昇順。
  final bool descending;

  WishSort copyWith({WishSortKey? key, bool? descending}) {
    return WishSort(
      key: key ?? this.key,
      descending: descending ?? this.descending,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WishSort &&
      other.key == key &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(key, descending);
}

/// 主キー比較。null は方向に依らず常に末尾（仕様8）。
int _compareByKey(WishItem a, WishItem b, WishSort sort) {
  switch (sort.key) {
    case WishSortKey.price:
      final cmp = a.price.compareTo(b.price);
      return sort.descending ? -cmp : cmp;
    case WishSortKey.createdAt:
      final cmp = a.createdAt.compareTo(b.createdAt);
      return sort.descending ? -cmp : cmp;
    case WishSortKey.purchasedAt:
      final av = a.purchasedAt;
      final bv = b.purchasedAt;
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      final cmp = av.compareTo(bv);
      return sort.descending ? -cmp : cmp;
  }
}

/// [items] を [sort] の条件で並び替えた新しいリストを返す（非破壊）。
/// 主キーが同値のときは追加日・降順で固定のタイブレークを行う（仕様9）。
List<WishItem> sortWishItems(List<WishItem> items, WishSort sort) {
  final sorted = [...items];
  sorted.sort((a, b) {
    final cmp = _compareByKey(a, b, sort);
    if (cmp != 0) return cmp;
    return b.createdAt.compareTo(a.createdAt);
  });
  return sorted;
}
