import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/adventure_log/data/daily_earnings_backfill.dart';
import 'package:task_manager/features/adventure_log/data/daily_earnings_repository.dart';
import 'package:task_manager/features/adventure_log/model/daily_earning.dart';
import 'package:task_manager/features/adventure_log/providers/adventure_log_providers.dart';

final dailyEarningsRepositoryProvider = Provider<DailyEarningsRepository>(
  (_) => DailyEarningsRepository(),
);

final dailyEarningsBackfillRepositoryProvider = Provider<DailyEarningsBackfill>(
  (_) => DailyEarningsBackfill(),
);

/// legacy tasks/wishlist が adventure_entries へ埋め戻された後でないと
/// 日次集計が漏れるため、既存の adventureLogBackfillProvider の完了を先に待つ。
final dailyEarningsBackfillProvider = FutureProvider<void>((ref) async {
  await ref.watch(adventureLogBackfillProvider.future);
  await ref.watch(dailyEarningsBackfillRepositoryProvider).backfillIfNeeded();
});

final dailyEarningsEntriesProvider =
    StreamProvider.autoDispose<List<DailyEarning>>((ref) {
      return ref.watch(dailyEarningsRepositoryProvider).watchAll();
    });

/// 期間切替の状態。永続化しない（デフォルト30日）。
class EarningsPeriodNotifier extends Notifier<EarningsPeriod> {
  @override
  EarningsPeriod build() => EarningsPeriod.month;
  void set(EarningsPeriod v) => state = v;
}

final earningsPeriodProvider =
    NotifierProvider<EarningsPeriodNotifier, EarningsPeriod>(
      EarningsPeriodNotifier.new,
    );

/// 期間窓に応じた集計データ。まだロード中/未取得なら null。
final earningsWindowDataProvider = Provider.autoDispose<EarningsWindowData?>((
  ref,
) {
  final entries = ref.watch(dailyEarningsEntriesProvider).asData?.value;
  if (entries == null) return null;
  final period = ref.watch(earningsPeriodProvider);
  return buildEarningsWindowData(
    allEarnings: entries,
    today: DateTime.now(),
    period: period,
  );
});
