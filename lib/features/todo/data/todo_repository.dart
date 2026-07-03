import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/models/calendar_task.dart';

/// ToDo（Eisenhower Matrix）用の Firestore リポジトリ。
/// 既存の users/{uid}/tasks コレクションを isTodo=true のドキュメントとして共用する。
class TodoRepository {
  TodoRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('tasks');

  /// isTodo=true の全タスクを監視する。orderIndex 昇順。
  Stream<List<CalendarTask>> watchTodos() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _col(uid)
        .where('isTodo', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => CalendarTask.fromMap(d.id, d.data()))
          .toList();
      // Firestore の orderBy を使うと欠損ドキュメントが除外されるため、クライアント側でソート
      list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return list;
    });
  }

  /// 新規 ToDo を作成する。デフォルトで右上（urgency=true, importance=true）。
  Future<String> createTodo({
    required String title,
    bool urgency = true,
    bool importance = true,
    int estimatedMinutes = 30,
    int orderIndex = 0,
    String? description,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final data = <String, dynamic>{
      'title': title,
      'reward': 0,
      'sourceType': 'manual',
      'isAllDay': false,
      'isCompleted': false,
      'isTodo': true,
      'urgency': urgency,
      'importance': importance,
      'orderIndex': orderIndex,
      'estimatedMinutes': estimatedMinutes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (description != null) data['description'] = description;
    final ref = await _col(uid).add(data);
    return ref.id;
  }

  /// 詳細シートからの更新（タイトル・メモ・所要時間・象限）。
  Future<void> upsert(CalendarTask task) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _col(uid).doc(task.id).update({
      'title': task.title,
      'urgency': task.urgency,
      'importance': task.importance,
      'orderIndex': task.orderIndex,
      'estimatedMinutes': task.estimatedMinutes,
      'note': task.note,
      'description': task.description ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 象限変更（drag & drop）。
  Future<void> updateQuadrant(
    String taskId, {
    required bool urgency,
    required bool importance,
    required int orderIndex,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _col(uid).doc(taskId).update({
      'urgency': urgency,
      'importance': importance,
      'orderIndex': orderIndex,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 象限内の並び順を一括更新する（同一象限内の並び替え／象限間移動の両方に使用）。
  /// orderIndex が実際に変わるドキュメントのみ書き込む。movedTaskId には
  /// urgency/importance/updatedAt も書き込む。
  Future<void> applyQuadrantOrder({
    required List<CalendarTask> orderedTasks,
    required String movedTaskId,
    required bool urgency,
    required bool importance,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    final batch = _db.batch();
    var hasWrite = false;
    for (var i = 0; i < orderedTasks.length; i++) {
      final task = orderedTasks[i];
      final isMoved = task.id == movedTaskId;
      if (task.orderIndex == i && !isMoved) continue;
      hasWrite = true;
      final data = <String, dynamic>{'orderIndex': i};
      if (isMoved) {
        data['urgency'] = urgency;
        data['importance'] = importance;
        data['updatedAt'] = FieldValue.serverTimestamp();
      }
      batch.update(_col(uid).doc(task.id), data);
    }
    if (!hasWrite) return;
    await batch.commit();
  }

  /// ToDo → カレンダー予定へ変換。isTodo=false + start/end を書き込む。
  Future<void> convertToCalendarEvent({
    required String taskId,
    required DateTime start,
    required DateTime end,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _col(uid).doc(taskId).update({
      'isTodo': false,
      'startAtUtc': Timestamp.fromDate(start.toUtc()),
      'endAtUtc': Timestamp.fromDate(end.toUtc()),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String taskId) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _col(uid).doc(taskId).delete();
  }
}
