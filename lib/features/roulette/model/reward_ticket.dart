import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';

/// 当たり（中／大）で発行されるご褒美チケット。`users/{uid}/reward_tickets/{id}`。
/// 期限なし。好きなタイミングで消費でき、消費すると [used] が true になる（在庫から外れる）。
/// 小当たりは「即時許可」でバンクしないため、チケットは中／大のみ。
class RewardTicket {
  const RewardTicket({
    required this.id,
    required this.tier,
    required this.rewardName,
    required this.wonAt,
    this.used = false,
    this.usedAt,
  });

  final String id;
  final RouletteCategory tier;
  final String rewardName;
  final DateTime wonAt;
  final bool used;
  final DateTime? usedAt;

  static RouletteCategory _tierFromWire(Object? raw) {
    return switch (raw) {
      'jackpot' => RouletteCategory.jackpot,
      'chu' => RouletteCategory.chu,
      'sho' => RouletteCategory.sho,
      _ => RouletteCategory.chu,
    };
  }

  static String tierToWire(RouletteCategory tier) => tier.name;

  factory RewardTicket.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final wonAt = data['wonAt'] as Timestamp?;
    final usedAt = data['usedAt'] as Timestamp?;
    return RewardTicket(
      id: doc.id,
      tier: _tierFromWire(data['tier']),
      rewardName: data['rewardName'] as String? ?? '',
      wonAt: wonAt?.toDate().toLocal() ?? DateTime.now(),
      used: data['used'] as bool? ?? false,
      usedAt: usedAt?.toDate().toLocal(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'tier': tierToWire(tier),
      'rewardName': rewardName,
      'wonAt': FieldValue.serverTimestamp(),
      'used': used,
    };
  }
}
