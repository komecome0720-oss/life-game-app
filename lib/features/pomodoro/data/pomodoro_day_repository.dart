import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/features/health/model/health_rollover.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_day.dart';

/// `users/{uid}/pomodoro_days/{dateKey}`（dateKey = ローカル yyyy-MM-dd）を
/// 扱うリポジトリ。「1日通しセット」の日次状態（サイクル位置・やりかけ作業
/// フェーズ・未消化休憩）を保持する。
///
/// [docRef] は static として公開し、`ActiveTimerRepository` のトランザクション
/// からも同じパスを参照できるようにする（呼び出し元の Firestore インスタンスを
/// そのまま渡すことで、テスト用の fake インスタンスでも同一トランザクション内で
/// 扱える）。
class PomodoroDayRepository {
  PomodoroDayRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    DateTime Function()? now,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _now = now ?? DateTime.now;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final DateTime Function() _now;

  static DocumentReference<Map<String, dynamic>> docRef(
    FirebaseFirestore db,
    String uid,
    String dateKey,
  ) {
    return db
        .collection('users')
        .doc(uid)
        .collection('pomodoro_days')
        .doc(dateKey);
  }

  /// 今日（端末ローカル日付）の day doc を1回だけ取得する。
  /// 未認証・doc 未作成なら null（「まっさら」として扱う）。
  Future<PomodoroDay?> readToday() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    // `_now()` は端末ローカル時刻（DateTime.now 相当）を返す想定。
    // HealthRollover.dateKey は toLocal しないため、ここで UTC を渡すと
    // 0:00-9:00 JST 帯で前日化するバグになる（呼び出し元の規約に注意）。
    final dateKey = HealthRollover.dateKey(_now());
    final snap = await docRef(_db, uid, dateKey).get();
    return PomodoroDay.fromMap(snap.data());
  }

  /// [dateKey] の day doc を監視する。未認証なら null を流す。
  Stream<PomodoroDay?> watch(String dateKey) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return docRef(_db, uid, dateKey)
        .snapshots()
        .map((snap) => PomodoroDay.fromMap(snap.data()));
  }
}
