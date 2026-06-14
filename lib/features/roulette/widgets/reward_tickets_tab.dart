import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';
import 'package:task_manager/features/roulette/model/reward_ticket.dart';
import 'package:task_manager/features/roulette/providers/roulette_providers.dart';
import 'package:task_manager/features/roulette/widgets/roulette_board.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/empty_state_view.dart';

/// 欲しいものリスト画面の「ご褒美チケット」タブ。中／大の未使用チケット在庫を表示し、消費できる。
class RewardTicketsTab extends ConsumerWidget {
  const RewardTicketsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTickets = ref.watch(unusedTicketsProvider);
    return asyncTickets.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('エラー: $e')),
      data: (tickets) {
        if (tickets.isEmpty) {
          return const Center(
            child: EmptyStateView(
              icon: Icons.confirmation_number_outlined,
              message: 'まだチケットがありません。\nタスクを達成してルーレットを回そう！',
            ),
          );
        }
        // 大→中の順でグルーピング（小は即時許可のためチケット化されない）。
        final jackpot =
            tickets.where((t) => t.tier == RouletteCategory.jackpot).toList();
        final chu =
            tickets.where((t) => t.tier == RouletteCategory.chu).toList();
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (jackpot.isNotEmpty)
              _TierSection(tier: RouletteCategory.jackpot, tickets: jackpot),
            if (chu.isNotEmpty)
              _TierSection(tier: RouletteCategory.chu, tickets: chu),
          ],
        );
      },
    );
  }
}

class _TierSection extends StatelessWidget {
  const _TierSection({required this.tier, required this.tickets});

  final RouletteCategory tier;
  final List<RewardTicket> tickets;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: RouletteBoard.colorFor(tier, scheme),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text('${tier.label}（${tickets.length}）',
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        ...tickets.map((t) => _TicketCard(ticket: t)),
      ],
    );
  }
}

class _TicketCard extends ConsumerWidget {
  const _TicketCard({required this.ticket});

  final RewardTicket ticket;

  Future<void> _confirmConsume(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ご褒美を使う'),
        content: Text('「${ticket.rewardName}」を使いますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('使った')),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(rouletteRepositoryProvider);
    final consumed = await repo.consumeTicket(ticket.id);
    if (!context.mounted) return;
    if (!consumed) {
      showAppSnackBar(
        context,
        const SnackBar(content: Text('このチケットはすでに使用済みです')),
      );
      return;
    }
    showAppSnackBar(
      context,
      SnackBar(
        content: Text('「${ticket.rewardName}」を使いました'),
        action: SnackBarAction(
          label: '元に戻す',
          onPressed: () => repo.restoreTicket(ticket.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final won = ticket.wonAt;
    final wonLabel = '${won.year}/${won.month}/${won.day} 獲得';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(Icons.confirmation_number,
            color: RouletteBoard.colorFor(ticket.tier, scheme)),
        title: Text(ticket.rewardName,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(wonLabel, style: text.bodySmall),
        trailing: OutlinedButton(
          onPressed: () => _confirmConsume(context, ref),
          child: const Text('使った'),
        ),
      ),
    );
  }
}
