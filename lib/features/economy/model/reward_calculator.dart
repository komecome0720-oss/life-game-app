/// 時間単価ベースの報酬額（円）を算出する。
/// [hourlyRate] または [minutes] が0以下の場合は0を返す（呼び出し側で
/// 既存reward等へのフォールバックが必要な場合は呼び出し側で判定すること）。
int rewardYenFor({required double hourlyRate, required int minutes}) {
  if (hourlyRate <= 0 || minutes <= 0) return 0;
  return (hourlyRate * minutes / 60).round();
}
