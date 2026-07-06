import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/timer/data/active_timer_repository.dart';
import 'package:task_manager/features/timer/model/active_timer.dart';

final activeTimerRepositoryProvider = Provider<ActiveTimerRepository>(
  (_) => ActiveTimerRepository(),
);

/// 現在のアクティブタイマー（存在しなければ null）を監視する。
final activeTimerStreamProvider = StreamProvider<ActiveTimer?>((ref) {
  return ref.watch(activeTimerRepositoryProvider).watch();
});
