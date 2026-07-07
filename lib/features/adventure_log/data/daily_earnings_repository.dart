import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/features/adventure_log/model/daily_earning.dart';

class DailyEarningsRepository {
  DailyEarningsRepository({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// 期間切替をローカル演算で行うため `daily_earnings` 全件を購読する
  /// （個人アプリの規模であれば数百〜千件程度で許容できる想定）。
  Stream<List<DailyEarning>> watchAll() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);

    return _db
        .collection('users')
        .doc(uid)
        .collection('daily_earnings')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(DailyEarning.fromFirestore).toList());
  }
}
