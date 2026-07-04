// 軽量単体テスト。Firebase 依存の widget smoke test は本プロジェクトでは
// 別途モック環境が必要なため、ここでは Pure Dart ロジックのみ検証する。

import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/utils/date_utils.dart';
import 'package:task_manager/features/calendar_sync/model/google_account_info.dart';

void main() {
  group('startOfWeek', () {
    test('月曜開始で水曜→月曜', () {
      final wed = DateTime(2026, 4, 22); // Wednesday
      final start = startOfWeek(wed, DateTime.monday);
      expect(start, DateTime(2026, 4, 20)); // Monday
    });

    test('日曜開始で水曜→前日曜', () {
      final wed = DateTime(2026, 4, 22);
      final start = startOfWeek(wed, DateTime.sunday);
      expect(start, DateTime(2026, 4, 19));
    });

    test('土曜開始で土曜→同日', () {
      final sat = DateTime(2026, 4, 25);
      final start = startOfWeek(sat, DateTime.saturday);
      expect(start, DateTime(2026, 4, 25));
    });
  });

  group('ExternalCalendarKey.tryParse', () {
    test('3要素形式（accountId:calendarId:eventId）', () {
      final key = ExternalCalendarKey.tryParse('acc1:cal2:evt3');
      expect(key, isNotNull);
      expect(key!.accountId, 'acc1');
      expect(key.calendarId, 'cal2');
      expect(key.eventId, 'evt3');
    });

    test('旧2要素形式（calendarId:eventId）', () {
      final key = ExternalCalendarKey.tryParse('cal:evt');
      expect(key, isNotNull);
      expect(key!.accountId, isNull);
      expect(key.calendarId, 'cal');
      expect(key.eventId, 'evt');
    });

    test('eventId にコロンが含まれる場合', () {
      final key = ExternalCalendarKey.tryParse('acc:cal:evt:with:colons');
      expect(key, isNotNull);
      expect(key!.accountId, 'acc');
      expect(key.calendarId, 'cal');
      expect(key.eventId, 'evt:with:colons');
    });

    test('null / 空文字', () {
      expect(ExternalCalendarKey.tryParse(null), isNull);
      expect(ExternalCalendarKey.tryParse(''), isNull);
    });
  });
}
