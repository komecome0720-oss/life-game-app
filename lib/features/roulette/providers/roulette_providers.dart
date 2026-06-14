import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/roulette/data/roulette_repository.dart';
import 'package:task_manager/features/roulette/data/roulette_service.dart';
import 'package:task_manager/features/roulette/model/reward_ticket.dart';

final rouletteRepositoryProvider = Provider<RouletteRepository>(
  (_) => RouletteRepository(),
);

final rouletteServiceProvider = Provider<RouletteService>(
  (ref) => RouletteService(ref.watch(rouletteRepositoryProvider)),
);

/// 未使用のご褒美チケット在庫（新しい順）。
final unusedTicketsProvider =
    StreamProvider.autoDispose<List<RewardTicket>>((ref) {
  return ref.watch(rouletteRepositoryProvider).watchUnusedTickets();
});
