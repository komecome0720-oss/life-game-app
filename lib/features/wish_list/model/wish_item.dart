import 'package:cloud_firestore/cloud_firestore.dart';

class WishItem {
  const WishItem({
    required this.id,
    required this.name,
    required this.price,
    this.shopUrl = '',
    this.imageUrl = '',
    this.isPurchased = false,
    this.purchasedAt,
    this.purchasedPriceYen,
    required this.createdAt,
    this.createdAtWasMissing = false,
  });

  final String id;
  final String name;
  final int price;
  final String shopUrl;
  final String imageUrl;
  final bool isPurchased;
  final DateTime? purchasedAt;
  final int? purchasedPriceYen;
  final DateTime createdAt;
  final bool createdAtWasMissing;

  factory WishItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final createdAt = data['createdAt'] as Timestamp?;
    final purchasedAt = data['purchasedAt'] as Timestamp?;
    return WishItem(
      id: doc.id,
      name: data['name'] as String? ?? '',
      price: (data['price'] as num?)?.toInt() ?? 0,
      shopUrl: data['shopUrl'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      isPurchased: data['isPurchased'] as bool? ?? false,
      purchasedAt: purchasedAt?.toDate().toLocal(),
      purchasedPriceYen: (data['purchasedPriceYen'] as num?)?.toInt(),
      createdAt: createdAt?.toDate() ?? DateTime.now(),
      createdAtWasMissing: createdAt == null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'price': price,
      'shopUrl': shopUrl,
      'imageUrl': imageUrl,
      'isPurchased': isPurchased,
      'createdAt': FieldValue.serverTimestamp(),
      if (purchasedAt != null)
        'purchasedAt': Timestamp.fromDate(purchasedAt!.toUtc()),
      if (purchasedPriceYen != null) 'purchasedPriceYen': purchasedPriceYen,
    };
  }

  WishItem copyWith({
    bool? isPurchased,
    DateTime? purchasedAt,
    int? purchasedPriceYen,
  }) {
    return WishItem(
      id: id,
      name: name,
      price: price,
      shopUrl: shopUrl,
      imageUrl: imageUrl,
      isPurchased: isPurchased ?? this.isPurchased,
      purchasedAt: purchasedAt ?? this.purchasedAt,
      purchasedPriceYen: purchasedPriceYen ?? this.purchasedPriceYen,
      createdAt: createdAt,
      createdAtWasMissing: createdAtWasMissing,
    );
  }
}
