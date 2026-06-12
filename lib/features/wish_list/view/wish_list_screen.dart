import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/wish_list/model/wish_item.dart';
import 'package:task_manager/features/wish_list/viewmodel/wish_list_viewmodel.dart';
import 'package:task_manager/features/wish_list/widgets/add_wish_item_sheet.dart';
import 'package:task_manager/features/wish_list/widgets/wish_item_card.dart';
import 'package:task_manager/widgets/empty_state_view.dart';
import 'package:task_manager/widgets/message_guard.dart';

class WishListScreen extends ConsumerWidget {
  const WishListScreen({super.key});

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddWishItemSheet(),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, WishItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${item.name}」を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () {
              ref.read(wishListProvider.notifier).deleteItem(item.id);
              Navigator.pop(ctx);
            },
            child: Text('削除', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItems = ref.watch(wishListProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('欲しいものリスト'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '未獲得'),
              Tab(text: '獲得済み'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'wish_list_fab',
          onPressed: () => _showAddSheet(context),
          child: const Icon(Icons.add),
        ),
        body: MessageGuard(
          child: asyncItems.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('エラー: $e')),
            data: (items) {
              final active = items.where((i) => !i.isPurchased).toList();
              final purchased = items.where((i) => i.isPurchased).toList();
              return TabBarView(
                children: [
                  _ItemList(items: active, onDelete: (item) => _confirmDelete(context, ref, item)),
                  _ItemList(items: purchased, onDelete: (item) => _confirmDelete(context, ref, item)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ItemList extends StatelessWidget {
  const _ItemList({required this.items, required this.onDelete});

  final List<WishItem> items;
  final void Function(WishItem) onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: EmptyStateView(
          icon: Icons.favorite_border,
          message: 'アイテムがありません',
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      itemBuilder: (_, i) => WishItemCard(
        item: items[i],
        onDelete: () => onDelete(items[i]),
      ),
    );
  }
}
