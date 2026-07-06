import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';

/// `users/{uid}/settings/pomodoro` を扱うリポジトリ。
/// ユーザー全体共通の1ドキュメント（タスク・端末に依存しない）。
class PomodoroSettingsRepository {
  PomodoroSettingsRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const _docId = 'pomodoro';

  DocumentReference<Map<String, dynamic>> _docRef(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('settings')
      .doc(_docId);

  String get _uidOrThrow {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    return uid;
  }

  /// 現在の設定を1回だけ取得する。未設定・未認証なら既定値を返す。
  Future<PomodoroSettings> read() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return PomodoroSettings.defaults;
    final snap = await _docRef(uid).get();
    return PomodoroSettings.fromMap(snap.data());
  }

  /// 設定を監視する。未設定・未認証なら既定値を流す。
  Stream<PomodoroSettings> watch() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(PomodoroSettings.defaults);
    return _docRef(uid)
        .snapshots()
        .map((snap) => PomodoroSettings.fromMap(snap.data()));
  }

  /// 設定を保存する（存在しなければ作成）。
  Future<void> save(PomodoroSettings settings) async {
    final uid = _uidOrThrow;
    await _docRef(uid).set(settings.toMap(), SetOptions(merge: true));
  }
}
