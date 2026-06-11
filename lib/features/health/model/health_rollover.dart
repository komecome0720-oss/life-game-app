/// 日次健康ログのロールオーバー判定ユーティリティ。
///
/// dateKey は `yyyy-MM-dd` 固定なので、文字列比較で日付順を判定できる。
class HealthRollover {
  HealthRollover._();

  static String dateKey(DateTime now) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${now.year.toString().padLeft(4, '0')}-${pad(now.month)}-${pad(now.day)}';
  }

  static bool isPastDateKey(String dateKey, String todayKey) =>
      dateKey.compareTo(todayKey) < 0;

  static bool shouldApplySaveResult({
    required String saveUid,
    required String? currentUid,
    required String saveDateKey,
    required String currentDateKey,
    required int saveGeneration,
    required int currentGeneration,
  }) {
    return saveUid == currentUid &&
        saveDateKey == currentDateKey &&
        saveGeneration == currentGeneration;
  }
}
