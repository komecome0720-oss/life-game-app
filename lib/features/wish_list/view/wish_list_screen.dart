import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/wish_list/model/wish_item.dart';
import 'package:task_manager/features/wish_list/model/wish_sort.dart';
import 'package:task_manager/features/wish_list/viewmodel/wish_list_viewmodel.dart';
import 'package:task_manager/features/wish_list/viewmodel/wish_sort_providers.dart';
import 'package:task_manager/features/roulette/widgets/reward_tickets_tab.dart';
import 'package:task_manager/features/wish_list/widgets/add_wish_item_sheet.dart';
import 'package:task_manager/features/wish_list/widgets/wish_item_card.dart';
import 'package:task_manager/features/wish_list/widgets/wish_sort_bar.dart';
import 'package:task_manager/widgets/empty_state_view.dart';
import 'package:task_manager/widgets/message_guard.dart';
import 'package:task_manager/widgets/quick_action_fab.dart';

class WishListScreen extends ConsumerWidget {
  const WishListScreen({super.key});

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddWishItemSheet(),
    );
  }

  void _showQuickPurchaseSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddWishItemSheet(quickPurchase: true),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, WishItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${item.name}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              ref.read(wishListProvider.notifier).deleteItem(item.id);
              Navigator.pop(ctx);
            },
            child: Text(
              '削除',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItems = ref.watch(wishListProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('欲しいものリスト'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '未獲得'),
              Tab(text: '獲得済み'),
              Tab(text: 'ご褒美チケット'),
            ],
          ),
        ),
        // 追加(+)FABはウィッシュアイテム用なので、チケットタブでは隠す。
        floatingActionButton: Builder(
          builder: (context) {
            final controller = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.index == 2) return const SizedBox.shrink();
                return QuickActionFab(
                  heroTag: 'wish_list_fab',
                  icon: Icons.add,
                  onTap: () => _showAddSheet(context),
                  actions: [
                    QuickAction(
                      icon: Icons.check,
                      tooltip: 'クイック購入',
                      onTrigger: () => _showQuickPurchaseSheet(context),
                    ),
                  ],
                );
              },
            );
          },
        ),
        body: MessageGuard(
          child: asyncItems.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('エラー: $e')),
            data: (items) {
              final active = items.where((i) => !i.isPurchased).toList();
              final purchased = items.where((i) => i.isPurchased).toList();
              return TabBarView(
                // カード左スワイプ削除と競合するため、タブの左右スワイプ切替は無効化。
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _ItemList(
                    items: active,
                    onDelete: (item) => _confirmDelete(context, ref, item),
                    sortProvider: activeWishSortProvider,
                    availableKeys: kActiveWishSortKeys,
                  ),
                  _ItemList(
                    items: purchased,
                    onDelete: (item) => _confirmDelete(context, ref, item),
                    sortProvider: purchasedWishSortProvider,
                    availableKeys: kPurchasedWishSortKeys,
                  ),
                  const RewardTicketsTab(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ItemList extends ConsumerWidget {
  const _ItemList({
    required this.items,
    required this.onDelete,
    required this.sortProvider,
    required this.availableKeys,
  });

  final List<WishItem> items;
  final void Function(WishItem) onDelete;
  final NotifierProvider<WishSortNotifier, WishSort> sortProvider;
  final List<WishSortKey> availableKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      // アイテム0件のタブでは並び替えバーを非表示にし、空表示のみとする。
      return const Center(
        child: EmptyStateView(
          icon: Icons.favorite_border,
          message: 'アイテムがありません',
        ),
      );
    }
    final sort = ref.watch(sortProvider);
    final sorted = sortWishItems(items, sort);
    return Column(
      children: [
        WishSortBar(sortProvider: sortProvider, availableKeys: availableKeys),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sorted.length,
            itemBuilder: (_, i) => WishItemCard(
              item: sorted[i],
              onDelete: () => onDelete(sorted[i]),
            ),
          ),
        ),
      ],
    );
  }
}
