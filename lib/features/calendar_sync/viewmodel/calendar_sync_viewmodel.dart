import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/calendar_sync/model/google_account_info.dart';
import 'package:task_manager/features/calendar_sync/model/google_calendar_source.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
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
  Future<bool> createTask({
    required String title,
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      await ref.read(calendarTaskSyncRepositoryProvider).createTask(
            title: title,
            start: start,
            end: end,
          );
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _toMessage(e));
      return false;
    }
  }

  /// タスクの開始時刻を [newStart] に変更する。所要時間は維持。
  /// Google由来ならカレンダー側も更新。失敗時は Firestore をロールバック。
  ///
  /// 引数の [task] が isTodo=true の場合は「ToDo → カレンダー予定化」として扱い、
  /// estimatedMinutes を duration として新規に start/end を書き込む。
  Future<bool> moveTask(CalendarTask task, DateTime newStart) async {
    final syncRepo = ref.read(calendarTaskSyncRepositoryProvider);

    // ToDo からカレンダーへのドロップ時は変換処理
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
      // 1. Firestore 即時更新（Streamを通じUIに反映）
      await syncRepo.moveTask(task, newStart, newEnd);

      // 2. Google イベントなら calendar 側も patch
      if (task.sourceType == TaskSourceType.googleCalendar &&
          task.externalCalendarId != null) {
        try {
          final key = ExternalCalendarKey.tryParse(task.externalCalendarId);
          if (key != null) {
            await ref.read(googleCalendarRepositoryProvider).patchEvent(
                  calendarId: key.calendarId,
                  eventId: key.eventId,
                  newStartLocal: newStart,
                  newEndLocal: newEnd,
                );
          }
        } catch (e) {
          // Google失敗時は Firestore ロールバック
          try {
            await syncRepo.moveTask(task, prevStart, prevEnd);
          } catch (_) {/* rollback失敗は無視 */}
          rethrow;
        }
      }
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _toMessage(e));
      return false;
    }
  }

  /// 詳細付きで新規タスクを作成。[calendarId] が指定されていれば Google Calendar にも insert。
  /// 戻り値は成功可否。
  Future<bool> saveNewTask({
    required String title,
    required DateTime start,
    required DateTime end,
    bool isAllDay = false,
    String? description,
    String? location,
    String? colorId,
    String? calendarId,
    List<String>? recurrence,
  }) async {
    final syncRepo = ref.read(calendarTaskSyncRepositoryProvider);
    final gcalRepo = ref.read(googleCalendarRepositoryProvider);
    try {
      String? externalId;
      var sourceType = TaskSourceType.manual;
      if (calendarId != null) {
        externalId = await gcalRepo.insertEvent(
          calendarId: calendarId,
          title: title,
          startLocal: start,
          endLocal: end,
          isAllDay: isAllDay,
          description: description,
          location: location,
          colorId: colorId,
          recurrence: recurrence,
        );
        sourceType = TaskSourceType.googleCalendar;
      }
      await syncRepo.createTaskFull(
        title: title,
        start: start,
        end: end,
        isAllDay: isAllDay,
        description: description,
        location: location,
        colorId: colorId,
        externalCalendarId: externalId,
        recurrence: recurrence,
        sourceType: sourceType,
      );
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _toMessage(e));
      return false;
    }
  }

  /// 既存タスクを更新。Google 由来なら events.patch も呼ぶ。
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
    final gcalRepo = ref.read(googleCalendarRepositoryProvider);
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
      );
      if (original.sourceType == TaskSourceType.googleCalendar &&
          original.externalCalendarId != null) {
        final key = ExternalCalendarKey.tryParse(original.externalCalendarId);
        if (key != null) {
          await gcalRepo.updateEvent(
            calendarId: key.calendarId,
            eventId: key.eventId,
            title: title,
            startLocal: start,
            endLocal: end,
            isAllDay: isAllDay,
            description: description,
            location: location,
            colorId: colorId,
            recurrence: recurrence,
          );
        }
      }
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _toMessage(e));
      return false;
    }
  }

  /// タスクを削除。Google 由来なら events.delete も呼ぶ（このインスタンスのみ）。
  Future<bool> deleteTask(CalendarTask task) async {
    final syncRepo = ref.read(calendarTaskSyncRepositoryProvider);
    final gcalRepo = ref.read(googleCalendarRepositoryProvider);
    try {
      if (task.sourceType == TaskSourceType.googleCalendar &&
          task.externalCalendarId != null) {
        final key = ExternalCalendarKey.tryParse(task.externalCalendarId);
        if (key != null) {
          await gcalRepo.deleteEvent(
            calendarId: key.calendarId,
            eventId: key.eventId,
          );
        }
      }
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
