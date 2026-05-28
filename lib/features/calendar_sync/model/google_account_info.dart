import 'package:flutter/foundation.dart';

/// 現在 Google Calendar 連携でアクティブな Google アカウントの情報。
@immutable
class GoogleAccountInfo {
  const GoogleAccountInfo({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  /// `GoogleSignInAccount.id`（安定）
  final String id;

  /// `GoogleSignInAccount.email`
  final String email;
  final String? displayName;
  final String? photoUrl;
}

/// externalCalendarId のパース結果。
@immutable
class ExternalCalendarKey {
  const ExternalCalendarKey({
    this.accountId,
    required this.calendarId,
    required this.eventId,
  });

  final String? accountId;
  final String calendarId;
  final String eventId;

  /// `accountId:calendarId:eventId` または旧形式 `calendarId:eventId` をパース。
  /// 旧形式の場合 accountId は null。
  static ExternalCalendarKey? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length == 2) {
      return ExternalCalendarKey(
        accountId: null,
        calendarId: parts[0],
        eventId: parts[1],
      );
    }
    if (parts.length >= 3) {
      return ExternalCalendarKey(
        accountId: parts[0],
        calendarId: parts[1],
        eventId: parts.sublist(2).join(':'),
      );
    }
    return null;
  }
}
