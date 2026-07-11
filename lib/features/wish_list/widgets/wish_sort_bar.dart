import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/wish_list/model/wish_sort.dart';
import 'package:task_manager/features/wish_list/viewmodel/wish_sort_providers.dart';

/// 各タブのリスト上部に置く並び替えバー。
/// 基準はドロップダウン、方向は矢印アイコンのトグルで切り替える。
class WishSortBar extends ConsumerWidget {
  const WishSortBar({
    super.key,
    required this.sortProvider,
    required this.availableKeys,
  });

  final NotifierProvider<WishSortNotifier, WishSort> sortProvider;
  final List<WishSortKey> availableKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(sortProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.sort, size: 18),
          const SizedBox(width: 8),
          // Row 直置きのため isExpanded は付けない（横方向 unbounded を避ける）。
          DropdownButtonHideUnderline(
            child: DropdownButton<WishSortKey>(
              value: sort.key,
              isDense: true,
              items: availableKeys
                  .map(
                    (k) => DropdownMenuItem(value: k, child: Text(k.label)),
                  )
                  .toList(),
              onChanged: (k) {
                if (k != null) ref.read(sortProvider.notifier).setKey(k);
              },
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              sort.descending ? Icons.arrow_downward : Icons.arrow_upward,
            ),
            tooltip: sort.descending ? '降順' : '昇順',
            onPressed: () => ref.read(sortProvider.notifier).toggleDirection(),
          ),
        ],
      ),
    );
  }
}
