import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/core/providers/firebase_providers.dart';
import 'package:task_manager/features/health/model/health_rollover.dart';
import 'package:task_manager/features/pomodoro/data/pomodoro_day_repository.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_day.dart';

final pomodoroDayRepositoryProvider = Provider<PomodoroDayRepository>(
  (_) => PomodoroDayRepository(),
);

/// [now] のローカル日付における、次のローカル0時ちょうどを返す純関数
/// （`currentDateKeyProvider` の更新タイミング計算をテスト可能にするため分離）。
DateTime nextMidnight(DateTime now) {
  final midnightToday = DateTime(now.year, now.month, now.day);
  return midnightToday.add(const Duration(days: 1));
}

/// 端末ローカルの現在日付（`yyyy-MM-dd`）。即時 emit し、次のローカル0時に
/// 自動更新する（「1日の区切りは端末ローカル0時」の仕様4に対応）。
final currentDateKeyProvider = StreamProvider<String>((ref) async* {
  while (true) {
    final now = DateTime.now();
    yield HealthRollover.dateKey(now);
    final wait = nextMidnight(now).difference(DateTime.now());
    await Future<void>.delayed(wait.isNegative ? Duration.zero : wait);
  }
});

/// 今日の day doc（`pomodoro_days/{dateKey}`）を監視する。doc なし → null。
final pomodoroDayStreamProvider = StreamProvider<PomodoroDay?>((ref) {
  final dateKey = ref.watch(currentDateKeyProvider).value;
  if (dateKey == null) return const Stream<PomodoroDay?>.empty();
  return ref.watch(pomodoroDayRepositoryProvider).watch(dateKey);
});

/// ホームの「今日：◯時間◯分（作業時間）／【◯円】（獲得金額）」表示用。
/// doc なし・未認証なら (taskYen: 0, workSeconds: 0)。
final todayEarningsStreamProvider =
    StreamProvider<({int taskYen, int workSeconds})>((ref) {
  const zero = (taskYen: 0, workSeconds: 0);
  final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
  final dateKey = ref.watch(currentDateKeyProvider).value;
  if (uid == null || dateKey == null) {
    return Stream.value(zero);
  }
  return ref
      .watch(firebaseFirestoreProvider)
      .collection('users')
      .doc(uid)
      .collection('daily_earnings')
      .doc(dateKey)
      .snapshots()
      .map((snap) {
    final data = snap.data();
    return (
      taskYen: (data?['taskYen'] as num?)?.toInt() ?? 0,
      workSeconds: (data?['workSeconds'] as num?)?.toInt() ?? 0,
    );
  });
});
