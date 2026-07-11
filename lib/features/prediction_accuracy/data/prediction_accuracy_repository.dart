import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/features/prediction_accuracy/model/prediction_accuracy_config.dart';
import 'package:task_manager/features/prediction_accuracy/model/prediction_accuracy_stats.dart';
import 'package:task_manager/models/calendar_task.dart';

/// 時間予測精度ゲームの集計データ取得を担う。
///
/// 予測・実績の両方が記録された完了タスクのみが対象（[CalendarTask.actualMinutes] は
/// 記録時に必ず正の値になるため `isCompleted` の等価クエリのみで絞り込み、
/// null/未記録分はクライアント側でフィルタする。単一の等価条件クエリのため
/// 追加の複合インデックス無しで動く）。
class PredictionAccuracyRepository {
  PredictionAccuracyRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _tasksCol(String uid) =>
      _db.collection('users').doc(uid).collection('tasks');

  /// 宣言済み予測・実績とも記録済みの完了タスクを、完了日時の新しい順に返す（リアルタイム反映）。
  /// [CalendarTask.predictionDeclared] が false（未宣言）のタスクは対象外
  /// （宣言制導入前の旧完了タスクを自動的に統計から除外する＝シーズン2リセット）。
  Stream<PredictionAccuracyStats> watchStats() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return Stream.value(
        const PredictionAccuracyStats(averageError: null, cumulativeCount: 0),
      );
    }
    return _tasksCol(uid)
        .where('isCompleted', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final tasks = snap.docs
          .map((doc) => CalendarTask.fromMap(doc.id, doc.data()))
          .where((t) =>
              t.predictionDeclared &&
              (t.predictedMinutes ?? 0) > 0 &&
              (t.actualMinutes ?? 0) > 0)
          .toList()
        ..sort((a, b) {
          final aAt = a.completedAt ?? DateTime(0);
          final bAt = b.completedAt ?? DateTime(0);
          return bAt.compareTo(aAt);
        });

      final errors = tasks
          .map((t) => PredictionAccuracyConfig.errorFor(
                predictedMinutes: t.predictedMinutes!,
                actualMinutes: t.actualMinutes!,
              ))
          .toList();

      return PredictionAccuracyStats(
        averageError: PredictionAccuracyConfig.rollingAverage(errors),
        cumulativeCount: tasks.length,
        windowCount: tasks.length < PredictionAccuracyConfig.rollingWindowSize
            ? tasks.length
            : PredictionAccuracyConfig.rollingWindowSize,
      );
    });
  }
}
