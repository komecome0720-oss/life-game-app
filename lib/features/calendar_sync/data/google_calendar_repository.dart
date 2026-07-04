import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:task_manager/features/calendar_sync/model/google_account_info.dart';
import 'package:task_manager/features/calendar_sync/model/google_calendar_source.dart';
import 'package:task_manager/models/calendar_task.dart';

class GoogleCalendarRepository {
  // 読み取り専用。Google カレンダーへ書き戻さない方針のため events スコープは要求しない
  // （制限付きスコープを外すことで配信時の CASA セキュリティ評価を回避できる）。
  static const _scopes = [
    'https://www.googleapis.com/auth/calendar.readonly',
  ];

  // clientId は明示せず、iOS は Info.plist の GIDClientID を自動採用させる
  // （ログイン用 AuthRepository と同方式）。明示指定すると macOS 用 ID 等と
  // 取り違えた際に URL スキーム検証に失敗してクラッシュするため。
  final _signIn = GoogleSignIn(scopes: _scopes);

  /// 認証済み CalendarApi を返す。キャンセル時は null。
  Future<gcal.CalendarApi?> _getApi() async {
    // サイレントで試みて失敗したら明示的サインイン（同意画面）
    var account = await _signIn.signInSilently();
    account ??= await _signIn.signIn();

    if (account == null) {
      debugPrint('GoogleCalendarRepository: signIn returned null (cancelled)');
      return null;
    }

    // 既存サインインで calendar スコープが未許可の場合に同意画面を出す。
    // AuthRepository 側は basic profile のみなので、初回は必ずここで要求が走る。
    final granted = await _signIn.requestScopes(_scopes);
    if (!granted) {
      debugPrint('GoogleCalendarRepository: calendar scope denied');
      return null;
    }

    final client = await _signIn.authenticatedClient();
    if (client == null) {
      debugPrint('GoogleCalendarRepository: authenticatedClient returned null');
      return null;
    }

    return gcal.CalendarApi(client);
  }

  /// 現在サインイン済みの Google アカウント情報（無ければ silent 試行）。
  Future<GoogleAccountInfo?> getCurrentAccount() async {
    final account = _signIn.currentUser ?? await _signIn.signInSilently();
    if (account == null) return null;
    return _toInfo(account);
  }

  /// ピッカー強制サインイン。現在サインイン中でもサインアウトして再ピッカーを出す。
  /// 別アカウントへの切替に使用。
  Future<GoogleAccountInfo?> signInWithPicker() async {
    try {
      await _signIn.signOut();
    } catch (_) {/* 未サインイン時は無視 */}
    final account = await _signIn.signIn();
    if (account == null) return null;
    final granted = await _signIn.requestScopes(_scopes);
    if (!granted) return null;
    return _toInfo(account);
  }

  GoogleAccountInfo _toInfo(GoogleSignInAccount a) => GoogleAccountInfo(
        id: a.id,
        email: a.email,
        displayName: a.displayName,
        photoUrl: a.photoUrl,
      );

  /// ユーザーのカレンダー一覧を取得する。
  Future<List<GoogleCalendarSource>> fetchCalendars() async {
    final api = await _getApi();
    if (api == null) throw Exception('カレンダーの認証がキャンセルされました');

    final list = await api.calendarList.list();
    return (list.items ?? [])
        .where((c) => c.id != null && c.summary != null)
        .map((c) => GoogleCalendarSource(
              id: c.id!,
              name: c.summary!,
              isPrimary: c.primary ?? false,
              colorHex: c.backgroundColor,
            ))
        .toList();
  }

  /// 指定カレンダーの指定週（月曜始まり・ローカル時刻基準）イベントを取得し
  /// [CalendarTask] リストに変換して返す。
  /// [accountId] が与えられれば externalCalendarId は `accountId:calendarId:eventId` 形式に。
  Future<List<CalendarTask>> fetchWeekEvents({
    required String calendarId,
    required DateTime weekStartLocal,
    String? accountId,
  }) async {
    final api = await _getApi();
    if (api == null) throw Exception('カレンダーの認証がキャンセルされました');

    final weekEndLocal = weekStartLocal.add(const Duration(days: 7));

    final events = await api.events.list(
      calendarId,
      timeMin: weekStartLocal.toUtc(),
      timeMax: weekEndLocal.toUtc(),
      singleEvents: true,
      orderBy: 'startTime',
    );

    final results = <CalendarTask>[];
    for (final event in events.items ?? []) {
      if (event.status == 'cancelled') continue;
      if (event.id == null) continue;

      final externalId = accountId == null
          ? '$calendarId:${event.id}'
          : '$accountId:$calendarId:${event.id}';
      bool isAllDay = false;
      DateTime startLocal;
      DateTime endLocal;

      if (event.start?.dateTime != null) {
        startLocal = event.start!.dateTime!.toLocal();
        endLocal = (event.end?.dateTime ?? event.start!.dateTime!).toLocal();
      } else if (event.start?.date != null) {
        // 終日予定: date のみ（時刻なし）
        isAllDay = true;
        final sd = event.start!.date!;
        startLocal = DateTime(sd.year, sd.month, sd.day);
        final ed = event.end?.date ?? sd;
        endLocal = DateTime(ed.year, ed.month, ed.day);
      } else {
        debugPrint('GoogleCalendarRepository: skipping event with no time: ${event.id}');
        continue;
      }

      results.add(CalendarTask(
        id: externalId,
        title: event.summary ?? '(タイトルなし)',
        start: startLocal,
        end: endLocal,
        rewardYen: 0,
        externalCalendarId: externalId,
        sourceType: TaskSourceType.googleCalendar,
        isAllDay: isAllDay,
        description: event.description,
        location: event.location,
        colorId: event.colorId,
        recurrence: event.recurrence,
        recurringEventId: event.recurringEventId,
      ));
    }

    return results;
  }
}
