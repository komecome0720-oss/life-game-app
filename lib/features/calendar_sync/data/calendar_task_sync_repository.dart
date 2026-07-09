import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:task_manager/models/calendar_task.dart';

class CalendarTaskSyncRepository {
  CalendarTaskSyncRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// [tasks] を Firestore へ upsert する。
  /// - externalCalendarId が同じ既存ドキュメントがあれば更新（isCompleted は保持）。
  /// - 未存在なら新規追加。
  Future<void> upsert(List<CalendarTask> tasks) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    if (tasks.isEmpty) return;

    final tasksCol = _db.collection('users').doc(uid).collection('tasks');

    final externalIds = tasks
        .map((t) => t.externalCalendarId)
        .whereType<String>()
        .toList();

    // whereIn の上限(30)に合わせてバッチ検索
    final existingRefs = <String, DocumentReference>{};
    final existingIsTodo = <String, bool>{};
    final existingRepositioned = <String, bool>{};
    for (var i = 0; i < externalIds.length; i += 30) {
      final chunk = externalIds.sublist(
        i,
        (i + 30) > externalIds.length ? externalIds.length : i + 30,
      );
      final snapshot = await tasksCol
          .where('externalCalendarId', whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        final extId = doc.data()['externalCalendarId'] as String?;
        if (extId != null) {
          existingRefs[extId] = doc.reference;
          existingIsTodo[extId] = doc.data()['isTodo'] as bool? ?? false;
          existingRepositioned[extId] =
              doc.data()['repositioned'] as bool? ?? false;
        }
      }
    }

    // WriteBatch で一括書き込み（上限500件。週1週間分なら通常問題なし）
    final batch = _db.batch();
    final serverNow = FieldValue.serverTimestamp();

    for (final task in tasks) {
      final extId = task.externalCalendarId;
      if (extId == null) continue;

      if (existingRefs.containsKey(extId)) {
        // ToDo化済みは Google 側データによる isTodo/start/end の巻き戻しを防ぐためスキップ
        if (existingIsTodo[extId] == true) continue;
        // 完了時に実績ベースで再配置済み（repositioned:true）のものは、
        // 再同期で元時刻に戻らないよう一切上書きしない
        if (existingRepositioned[extId] == true) continue;
        // 更新: 完了状態とログはユーザー操作値を保持するため除外
        final updateData = task.toMap()
          ..remove('isCompleted')
          ..remove('completedAtUtc')
          ..remove('predictedMinutes')
          ..remove('actualMinutes')
          ..remove('urgency')
          ..remove('importance')
          ..['updatedAt'] = serverNow;
        batch.update(existingRefs[extId]!, updateData);
      } else {
        final ref = tasksCol.doc();
        batch.set(ref, task.toMap()..['updatedAt'] = serverNow);
      }
    }

    await batch.commit();
  }

  /// 手動タスクを新規作成する。
  Future<void> createTask({
    required String title,
    required DateTime start,
    required DateTime end,
    bool urgency = true,
    bool importance = true,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db.collection('users').doc(uid).collection('tasks').add({
      'title': title,
      'startAtUtc': Timestamp.fromDate(start.toUtc()),
      'endAtUtc': Timestamp.fromDate(end.toUtc()),
      'reward': 0,
      'sourceType': 'manual',
      'isAllDay': false,
      'isCompleted': false,
      'urgency': urgency,
      'importance': importance,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 指定タスクの開始・終了時刻を変更する。所要時間は [task] から算出。
  Future<void> moveTask(
    CalendarTask task,
    DateTime newStart,
    DateTime newEnd,
  ) async {
    await moveTaskById(taskId: task.id, newStart: newStart, newEnd: newEnd);
  }

  /// 指定タスクIDの開始・終了時刻を変更し、実績ベースの再配置であることを示す
  /// `repositioned:true` を同一書き込みで立てる。以降 upsert / deleteTasksByCalendarInWeek
  /// はこのフラグが立ったドキュメントを保護し、位置を上書き・削除しない。
  Future<void> moveTaskById({
    required String taskId,
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc(taskId)
        .update({
          'startAtUtc': Timestamp.fromDate(newStart.toUtc()),
          'endAtUtc': Timestamp.fromDate(newEnd.toUtc()),
          'repositioned': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> updateQuadrant({
    required String taskId,
    required bool urgency,
    required bool importance,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc(taskId)
        .update({
          'urgency': urgency,
          'importance': importance,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  /// 手動タスクまたは Google タスクの詳細を更新。指定されたフィールドのみ上書き。
  Future<void> updateTask({
    required String taskId,
    String? title,
    DateTime? start,
    DateTime? end,
    bool? isAllDay,
    String? description,
    String? location,
    String? colorId,
    List<String>? recurrence,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (title != null) data['title'] = title;
    if (start != null) data['startAtUtc'] = Timestamp.fromDate(start.toUtc());
    if (end != null) data['endAtUtc'] = Timestamp.fromDate(end.toUtc());
    if (isAllDay != null) data['isAllDay'] = isAllDay;
    if (description != null) data['description'] = description;
    if (location != null) data['location'] = location;
    if (colorId != null) data['colorId'] = colorId;
    if (recurrence != null) data['recurrence'] = recurrence;
    await _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc(taskId)
        .update(data);
  }

  /// 未了のまま、入力中の予測時間・実績時間だけを保存する（「保存して中断」）。
  /// isCompleted は変更しない。
  Future<void> saveProgress({
    required String taskId,
    required int predictedMinutes,
    required int? actualMinutes,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    final data = <String, dynamic>{
      'predictedMinutes': predictedMinutes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (actualMinutes != null) data['actualMinutes'] = actualMinutes;
    await _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc(taskId)
        .update(data);
  }

  /// 完了タスクを未了に戻す。actualMinutes / predictedMinutes は保持し、
  /// isCompleted と completedAtUtc のみリセットする。
  Future<void> uncompleteTask({required String taskId}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc(taskId)
        .update({
          'isCompleted': false,
          'completedAtUtc': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  /// 新規タスクを Firestore に作成（詳細フィールド込み）。
  /// 戻り値は生成された taskId。
  Future<String> createTaskFull({
    required String title,
    required DateTime start,
    required DateTime end,
    bool isAllDay = false,
    String? description,
    String? location,
    String? colorId,
    String? externalCalendarId,
    List<String>? recurrence,
    TaskSourceType sourceType = TaskSourceType.manual,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    final doc = await _db.collection('users').doc(uid).collection('tasks').add({
      'title': title,
      'startAtUtc': Timestamp.fromDate(start.toUtc()),
      'endAtUtc': Timestamp.fromDate(end.toUtc()),
      'reward': 0,
      'sourceType': sourceType.name,
      'isAllDay': isAllDay,
      'isCompleted': false,
      'isTodo': false,
      'externalCalendarId': ?externalCalendarId,
      'description': ?description,
      'location': ?location,
      'colorId': ?colorId,
      'recurrence': ?recurrence,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// taskId からタスク単体を取得する。存在しなければ null（削除済み等）。
  Future<CalendarTask?> fetchTaskById(String taskId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc(taskId)
        .get();
    final data = doc.data();
    if (data == null) return null;
    return CalendarTask.fromMap(doc.id, data);
  }

  /// externalCalendarId に一致する既存タスクの Firestore ID を返す。
  /// 見つからなければ null（未保存）。
  Future<String?> findTaskIdByExternalId(String externalCalendarId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .where('externalCalendarId', isEqualTo: externalCalendarId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  /// タスクを Firestore から削除。
  Future<void> deleteTask(String taskId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc(taskId)
        .delete();
  }

  /// 指定カレンダーの指定週ぶんの取り込み済みタスクをすべて削除する。
  /// externalCalendarId のフォーマットは "calendarId:eventId" または
  /// "accountId:calendarId:eventId" の双方を想定し、parts[0] か parts[1] が
  /// [calendarId] と一致するものを対象にする。
  ///
  /// 「取り込んだだけで何もしていない」予定のみ削除する。以下は保護され残る：
  /// - isCompleted == true（完了済み・報酬付与済み）
  /// - actualMinutes != null（タイマー/実績入力済みだが未完了）
  /// - isTodo == true（ToDo化済み。start=null のため startAtUtc 範囲クエリで
  ///   そもそもヒットしないが、仕様として明記）
  Future<void> deleteTasksByCalendarInWeek({
    required String calendarId,
    required DateTime weekStartLocal,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    final weekEndLocal = weekStartLocal.add(const Duration(days: 7));
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .where('startAtUtc',
            isGreaterThanOrEqualTo: Timestamp.fromDate(weekStartLocal.toUtc()))
        .where('startAtUtc',
            isLessThan: Timestamp.fromDate(weekEndLocal.toUtc()))
        .get();

    final targets = <DocumentReference>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final ext = data['externalCalendarId'] as String?;
      if (ext == null) continue;
      if (data['isCompleted'] == true) continue;
      if (data['actualMinutes'] != null) continue;
      if (data['repositioned'] == true) continue;
      final parts = ext.split(':');
      // 旧形式: calendarId:eventId / 新形式: accountId:calendarId:eventId
      final extCalId = parts.length == 2
          ? parts[0]
          : (parts.length >= 3 ? parts[1] : null);
      if (extCalId == calendarId) targets.add(doc.reference);
    }
    if (targets.isEmpty) return;
    for (var i = 0; i < targets.length; i += 450) {
      final batch = _db.batch();
      final end = (i + 450) > targets.length ? targets.length : i + 450;
      for (final ref in targets.sublist(i, end)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  /// ToDo タスクをカレンダー予定に変換する（isTodo=false にして start/end を書き込む）。
  Future<void> convertToCalendarEvent({
    required String taskId,
    required DateTime start,
    required DateTime end,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc(taskId)
        .update({
          'isTodo': false,
          'startAtUtc': Timestamp.fromDate(start.toUtc()),
          'endAtUtc': Timestamp.fromDate(end.toUtc()),
          'repositioned': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  /// カレンダー予定（アプリ内タスク or ダウンロード済み Google 予定）を ToDo に変換する
  /// （isTodo=true にして start/end を消去）。
  /// externalCalendarId・isCompleted・actualMinutes・predictedMinutes は変更しない。
  Future<void> convertToTodo({
    required String taskId,
    required bool urgency,
    required bool importance,
    required int orderIndex,
    required int estimatedMinutes,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    await _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc(taskId)
        .update({
          'isTodo': true,
          'startAtUtc': FieldValue.delete(),
          'endAtUtc': FieldValue.delete(),
          'urgency': urgency,
          'importance': importance,
          'orderIndex': orderIndex,
          'estimatedMinutes': estimatedMinutes,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }
}
