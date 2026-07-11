import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/calendar_sync/model/google_calendar_source.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/features/timer/providers/timer_providers.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';

class CalendarSyncState {
  const CalendarSyncState({
    this.isLoading = false,
    this.errorMessage,
    this.calendars = const [],
  });

  final bool isLoading;
  final String? errorMessage;
  final List<GoogleCalendarSource> calendars;

  CalendarSyncState copyWith({
    bool? isLoading,
    String? errorMessage,
    List<GoogleCalendarSource>? calendars,
  }) {
    return CalendarSyncState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      calendars: calendars ?? this.calendars,
    );
  }
}

class CalendarSyncViewModel extends Notifier<CalendarSyncState> {
  @override
  CalendarSyncState build() => const CalendarSyncState();

  /// カレンダー一覧を取得して返す。失敗時は errorMessage を設定し空リストを返す。
  Future<List<GoogleCalendarSource>> loadCalendars() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final calendars =
          await ref.read(googleCalendarRepositoryProvider).fetchCalendars();
      state = state.copyWith(isLoading: false, calendars: calendars);
      return calendars;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _toMessage(e));
      return [];
    }
  }

  /// 指定カレンダーの weekStart 週分を取り込む。
  /// [accountId] 指定時は externalCalendarId を `accountId:calendarId:eventId` 形式で保存し、
  /// remoteWeekEventsProvider が返すIDと一致するため重複表示を防げる。
  Future<bool> importWeek({
    required String calendarId,
    required DateTime weekStart,
    String? accountId,
    int defaultQuadrant = 1,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final tasks = await ref.read(googleCalendarRepositoryProvider).fetchWeekEvents(
            calendarId: calendarId,
            weekStartLocal: weekStart,
            accountId: accountId,
          );

      final q = QuadrantX.fromNumber(defaultQuadrant);
      final withQuadrant = tasks
          .map((t) => t.copyWith(urgency: q.urgency, importance: q.importance))
          .toList();

      await ref.read(calendarTaskSyncRepositoryProvider).upsert(withQuadrant);

      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _toMessage(e));
      return false;
    }
  }

  /// リモート表示中の Google Calendar イベントをアプリ DB（Firestore）に
  /// 初めて保存する。既に externalCalendarId で保存されていれば何もしない（重複抑止）。
  /// 戻り値：保存された（または既存の）タスクの Firestore ID。キャンセル/失敗時は null。
  Future<String?> promoteRemoteTaskIfNeeded(CalendarTask task) async {
    final extId = task.externalCalendarId;
    if (extId == null) return task.id; // 手動タスクは既にDB保存済み想定
    final repo = ref.read(calendarTaskSyncRepositoryProvider);

    // 既存チェック
    final existingId = await repo.findTaskIdByExternalId(extId);
    if (existingId != null) return existingId;

    final start = task.start;
    final end = task.end;
    if (start == null || end == null) return null;

    try {
      final newId = await repo.createTaskFull(
        title: task.title,
        start: start,
        end: end,
        isAllDay: task.isAllDay,
        description: task.description,
        location: task.location,
        colorId: task.colorId,
        externalCalendarId: extId,
        recurrence: task.recurrence,
        sourceType: TaskSourceType.googleCalendar,
      );
      return newId;
    } catch (e) {
      state = state.copyWith(errorMessage: _toMessage(e));
      return null;
    }
  }

  /// 手動タスクを新規作成する。
  /// [estimatedMinutes]/[predictionDeclared] は空きスロットからの予定作成（宣言＝枠）用。
  Future<bool> createTask({
    required String title,
    required DateTime start,
    required DateTime end,
    bool urgency = true,
    bool importance = true,
    int? estimatedMinutes,
    bool predictionDeclared = false,
  }) async {
    try {
      await ref.read(calendarTaskSyncRepositoryProvider).createTask(
            title: title,
            start: start,
            end: end,
            urgency: urgency,
            importance: importance,
            estimatedMinutes: estimatedMinutes,
            predictionDeclared: predictionDeclared,
          );
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _toMessage(e));
      return false;
    }
  }

  /// タスクの開始時刻を [newStart] に変更する。所要時間は維持。
  /// 読み取り専用方針のため Google カレンダーへは書き戻さず、Firestore のみ更新する。
  ///
  /// 引数の [task] が isTodo=true の場合は「ToDo → カレンダー予定化」として扱い、
  /// estimatedMinutes を duration として新規に start/end を書き込む。
  Future<bool> moveTask(CalendarTask task, DateTime newStart) async {
    final syncRepo = ref.read(calendarTaskSyncRepositoryProvider);

    // ToDo からカレンダーへのドロップ時は変換処理。
    // ここでの 30分フォールバックは枠（表示上の長さ）のみに使うスケジューリング用途で、
    // 宣言状態（predictionDeclared・estimatedMinutes）には影響しない
    // （convertToCalendarEvent は update で該当フィールドに触れないため保持される）。
    if (task.isTodo) {
      final durationMin = task.estimatedMinutes ?? 30;
      final newEnd = newStart.add(Duration(minutes: durationMin));
      try {
        await syncRepo.convertToCalendarEvent(
          taskId: task.id,
          start: newStart,
          end: newEnd,
        );
        return true;
      } catch (e) {
        state = state.copyWith(errorMessage: _toMessage(e));
        return false;
      }
    }

    final prevStart = task.start;
    final prevEnd = task.end;
    if (prevStart == null || prevEnd == null) return false;
    if (prevStart == newStart) return true;
    final duration = prevEnd.difference(prevStart);
    final newEnd = newStart.add(duration);

    try {
      // Firestore のみ更新（Streamを通じUIに反映）。Google 側は変更しない。
      await syncRepo.moveTask(task, newStart, newEnd);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _toMessage(e));
      return false;
    }
  }

  /// 詳細付きで新規タスクを作成する。
  /// 読み取り専用方針のため Google カレンダーへは作成せず、常にローカル（手動）タスクとして保存する。
  Future<bool> saveNewTask({
    required String title,
    required DateTime start,
    required DateTime end,
    bool isAllDay = false,
    String? description,
    String? location,
    String? colorId,
    List<String>? recurrence,
    bool urgency = true,
    bool importance = true,
    int? estimatedMinutes,
    bool predictionDeclared = false,
  }) async {
    final syncRepo = ref.read(calendarTaskSyncRepositoryProvider);
    try {
      await syncRepo.createTaskFull(
        title: title,
        start: start,
        end: end,
        isAllDay: isAllDay,
        description: description,
        location: location,
        colorId: colorId,
        externalCalendarId: null,
        recurrence: recurrence,
        sourceType: TaskSourceType.manual,
        urgency: urgency,
        importance: importance,
        estimatedMinutes: estimatedMinutes,
        predictionDeclared: predictionDeclared,
      );
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _toMessage(e));
      return false;
    }
  }

  /// 既存タスクを更新する。
  /// 読み取り専用方針のため、取り込み済み（Google 由来）タスクでも Firestore のみ更新し、
  /// Google カレンダーへは書き戻さない（取り込み後は断絶＝ローカルの独立コピー）。
  ///
  /// 「枠リサイズ＝再宣言」（確定仕様7）: manual・宣言済み・未完了の予定で start/end が
  /// 変わる場合、estimatedMinutes を新しい枠の分数へ同期する（同一 update 内で書く）。
  /// 該当タスクの ActiveTimer が作動中は、タイマー側が正のため同期しない。
  Future<bool> updateExistingTask({
    required CalendarTask original,
    required String title,
    required DateTime start,
    required DateTime end,
    bool isAllDay = false,
    String? description,
    String? location,
    String? colorId,
    List<String>? recurrence,
  }) async {
    final syncRepo = ref.read(calendarTaskSyncRepositoryProvider);
    final frameChanged = original.start != start || original.end != end;
    final canResync = original.sourceType == TaskSourceType.manual &&
        original.predictionDeclared &&
        !original.isCompleted &&
        frameChanged &&
        ref.read(activeTimerStreamProvider).value?.taskId != original.id;
    try {
      await syncRepo.updateTask(
        taskId: original.id,
        title: title,
        start: start,
        end: end,
        isAllDay: isAllDay,
        description: description ?? '',
        location: location ?? '',
        colorId: colorId ?? '',
        recurrence: recurrence ?? const [],
        estimatedMinutes: canResync ? _frameMinutes(start, end) : null,
      );
      // 作動中タイマーが同タスクなら active_timer.taskTitle も同期する
      // （失敗しても保存全体は失敗扱いにしない＝表示追従用のため個別に握りつぶす）。
      final activeTimer = ref.read(activeTimerStreamProvider).value;
      if (activeTimer != null &&
          activeTimer.taskId == original.id &&
          activeTimer.taskTitle != title) {
        try {
          await ref.read(activeTimerRepositoryProvider).updateTaskTitle(title);
        } catch (_) {
          // no-op: active_timer 側の追従失敗は保存成否に影響させない。
        }
      }
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _toMessage(e));
      return false;
    }
  }

  /// 開始・終了時刻から枠の長さ（分）を算出する（0〜1440分にクランプ）。
  int _frameMinutes(DateTime start, DateTime end) {
    final m = end.difference(start).inMinutes;
    if (m < 0) return 0;
    if (m > 24 * 60) return 24 * 60;
    return m;
  }

  /// タスクを削除する。
  /// 読み取り専用方針のため Firestore のみ削除し、Google カレンダーの予定は残す。
  Future<bool> deleteTask(CalendarTask task) async {
    final syncRepo = ref.read(calendarTaskSyncRepositoryProvider);
    try {
      await syncRepo.deleteTask(task.id);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _toMessage(e));
      return false;
    }
  }

  void clearError() => state = state.copyWith(errorMessage: null);

  String _toMessage(Object e) {
    final raw = e.toString();
    debugPrint('CalendarSyncViewModel error: $raw');
    final msg = raw.toLowerCase();
    if (msg.contains('cancel') || msg.contains('キャンセル')) return 'キャンセルされました';
    if (msg.contains('socket') || msg.contains('network') || msg.contains('failed host lookup')) {
      return 'ネットワークエラーが発生しました';
    }
    if (msg.contains('has not been used') || msg.contains('disabled') || msg.contains('accessnotconfigured')) {
      return 'Google Calendar API が有効化されていません。Cloud Console で有効にしてください。';
    }
    if (msg.contains('403')) return 'アクセス権限エラー (403)。OAuth スコープを確認してください。';
    if (msg.contains('401')) return '認証エラー (401)。再度サインインしてください。';
    if (msg.contains('sign_in_failed') || msg.contains('platformexception')) {
      return 'Googleサインインに失敗しました: $raw';
    }
    // デバッグ用に実際のエラーを表示
    return 'エラー: $raw';
  }
}
