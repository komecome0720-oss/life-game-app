import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/health/model/health_rollover.dart';

void main() {
  group('HealthRollover', () {
    test('dateKey formats a local date as yyyy-MM-dd', () {
      expect(
        HealthRollover.dateKey(DateTime(2026, 6, 9, 23, 59)),
        '2026-06-09',
      );
    });

    test('isPastDateKey detects only dates before today', () {
      expect(HealthRollover.isPastDateKey('2026-06-08', '2026-06-09'), isTrue);
      expect(HealthRollover.isPastDateKey('2026-06-09', '2026-06-09'), isFalse);
      expect(HealthRollover.isPastDateKey('2026-06-10', '2026-06-09'), isFalse);
    });

    test('save result applies only to the same uid, date, and generation', () {
      expect(
        HealthRollover.shouldApplySaveResult(
          saveUid: 'u1',
          currentUid: 'u1',
          saveDateKey: '2026-06-09',
          currentDateKey: '2026-06-09',
          saveGeneration: 3,
          currentGeneration: 3,
        ),
        isTrue,
      );

      expect(
        HealthRollover.shouldApplySaveResult(
          saveUid: 'u1',
          currentUid: 'u1',
          saveDateKey: '2026-06-08',
          currentDateKey: '2026-06-09',
          saveGeneration: 3,
          currentGeneration: 4,
        ),
        isFalse,
      );
    });
  });
}
