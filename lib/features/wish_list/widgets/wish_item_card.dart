import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/features/wish_list/model/wish_item.dart';
import 'package:task_manager/features/wish_list/view/wish_item_completion_screen.dart';
import 'package:task_manager/features/wish_list/viewmodel/wish_list_viewmodel.dart';
import 'package:task_manager/features/wish_list/widgets/add_wish_item_sheet.dart';
import 'package:task_manager/utils/app_messenger.dart';

class WishItemCard extends ConsumerWidget {
  const WishItemCard({super.key, required this.item, required this.onDelete});

  final WishItem item;
  final VoidCallback onDelete;

  String _formatMoney(int n) {
    return n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy/MM/dd').format(date.toLocal());
  }

  String get _purchasedDateText {
    if (!item.isPurchased) return '未獲得';
    final purchasedAt = item.purchasedAt;
    if (purchasedAt == null) return '未記録';
    return _formatDate(purchasedAt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider).settings;
    final balanceYen = settings.totalEarned;
    final colorScheme = Theme.of(context).colorScheme;

    final text = Theme.of(context).textTheme;
    final canAcquire = !item.isPurchased && balanceYen >= item.price;

    return Slidable(
      key: ValueKey('wish_${item.id}'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) => onDelete(),
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
            icon: Icons.delete,
            label: '削除',
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: InkWell(
          onTap: () => _showEditSheet(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 画像
                if (item.imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      item.imageUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(colorScheme),
                    ),
                  )
                else
                  _placeholder(colorScheme),
                const SizedBox(width: 12),
                // 情報
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '¥${_formatMoney(item.price)}',
                        style: text.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '追加日：${_formatDate(item.createdAt)}',
                        style: text.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (item.isPurchased)
                        Text(
                          '獲得日：$_purchasedDateText',
                          style: text.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // アクション
                Column(
                  children: [
                    if (item.shopUrl.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.open_in_new, size: 20),
                        tooltip: 'ショップを開く',
                        onPressed: () {
                          /* URL launch は後で実装 */
                        },
                      ),
                    if (!item.isPurchased)
                      if (canAcquire)
                        IconButton(
                          icon: Icon(
                            Icons.check_circle_outline,
                            color: colorScheme.primary,
                          ),
                          tooltip: '獲得済みにする',
                          onPressed: () => _confirmAcquire(context, ref),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Column(
                            children: [
                              Text(
                                'あと',
                                style: text.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '¥${_formatMoney(item.price - balanceYen)}',
                                style: text.labelMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )
                    else
                      IconButton(
                        icon: const Icon(Icons.undo, size: 20),
                        tooltip: '未獲得に戻す',
                        onPressed: () async {
                          final result = await ref
                              .read(wishListProvider.notifier)
                              .togglePurchased(item);
                          if (result.missingAmount && context.mounted) {
                            showAppSnackBar(
                              context,
                              const SnackBar(
                                content: Text('過去データの金額が未記録のため戻せません'),
                              ),
                            );
                          }
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddWishItemSheet(item: item),
    );
  }

  void _confirmAcquire(BuildContext context, WidgetRef ref) {
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('獲得しましたか？'),
        content: Text('「${item.name}」（¥${_formatMoney(item.price)}）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final settings = ref.read(userSettingsProvider).settings;
              final ok = await ref
                  .read(wishListProvider.notifier)
                  .togglePurchased(item);
              if (ok.insufficientFunds) {
                if (context.mounted) {
                  showAppSnackBar(
                    context,
                    const SnackBar(content: Text('所持金が足りません')),
                  );
                }
                return;
              }
              if (ok.missingAmount) {
                if (context.mounted) {
                  showAppSnackBar(
                    context,
                    const SnackBar(content: Text('金額が未記録のため処理できません')),
                  );
                }
                return;
              }
              if (!ok.applied) return;
              navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => WishItemCompletionScreen(
                    userName: settings.displayName,
                    itemPrice: item.price,
                    balanceBeforeYen: ok.balanceBeforeYen,
                    balanceAfterYen: ok.balanceAfterYen,
                  ),
                ),
              );
            },
            child: const Text('獲得'),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme c) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: c.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.favorite_border, color: c.primary),
    );
  }
}
