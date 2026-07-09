/// 食事・睡眠・運動・瞑想は 0〜10。
/// 合計は重み付けして100点満点（食事・睡眠 ×3、運動・瞑想 ×2）。
/// [meditationEnabled] が false の場合、瞑想は合計・満点から除外され満点は80になる。
class HealthScores {
  const HealthScores({
    required this.meal,
    required this.sleep,
    required this.exercise,
    required this.meditation,
    this.meditationEnabled = true,
  });

  final int meal;
  final int sleep;
  final int exercise;
  final int meditation;
  final bool meditationEnabled;

  int get maxTotal => meditationEnabled ? 100 : 80;

  int get total =>
      meal * 3 +
      sleep * 3 +
      exercise * 2 +
      (meditationEnabled ? meditation * 2 : 0);
}
