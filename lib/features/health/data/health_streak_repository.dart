import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/features/health/model/health_streak_state.dart';

/// `users/{uid}/healthState/streak`（doc id 固定）の read/write。
/// ストリークはお金に触れない（非現金：称号＋フリーズのみ）ため、economy 側の
/// トランザクション（残高・台帳）とは独立した単純な get/set(merge) でよい。
class HealthStreakRepository {
  HealthStreakRepository({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _docRef(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('healthState')
      .doc('streak');

  Future<HealthStreakState> load() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const HealthStreakState();
    final doc = await _docRef(uid).get();
    if (!doc.exists) return const HealthStreakState();
    return HealthStreakState.fromFirestore(doc);
  }

  Future<void> save(HealthStreakState state) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _docRef(uid).set(state.toFirestore(), SetOptions(merge: true));
  }
}
