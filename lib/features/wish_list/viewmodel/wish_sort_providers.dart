import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/wish_list/model/wish_sort.dart';

/// 並び替え条件の状態。永続化しない（メモリ保持のみ・アプリ再起動で初期化）。
class WishSortNotifier extends Notifier<WishSort> {
  WishSortNotifier(this._initial);

  final WishSort _initial;

  @override
  WishSort build() => _initial;

  /// 基準を切り替える。方向は維持する（仕様11）。
  void setKey(WishSortKey key) => state = state.copyWith(key: key);

  void toggleDirection() => state = state.copyWith(descending: !state.descending);
}

/// 未獲得タブの並び順。初期値は追加日・降順。
final activeWishSortProvider = NotifierProvider<WishSortNotifier, WishSort>(
  () => WishSortNotifier(
    const WishSort(key: WishSortKey.createdAt, descending: true),
  ),
);

/// 獲得済みタブの並び順。初期値は獲得日・降順。
final purchasedWishSortProvider = NotifierProvider<WishSortNotifier, WishSort>(
  () => WishSortNotifier(
    const WishSort(key: WishSortKey.purchasedAt, descending: true),
  ),
);
