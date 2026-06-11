import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/features/adventure_log/data/adventure_log_backfill.dart';
import 'package:task_manager/features/adventure_log/model/adventure_log_entry.dart';

void main() {
  group('filterPendingAdventureBackfills', () {
    test('removes entries whose type and sourceId already exist', () {
      final drafts = [
        AdventureBackfillDraft(
          type: AdventureEntryType.taskCompleted,
          sourceId: 'task-1',
          title: 'Deep work',
          deltaYen: 1200,
          occurredAt: DateTime(2026, 6, 1, 9),
        ),
        AdventureBackfillDraft(
          type: AdventureEntryType.wishPurchased,
          sourceId: 'wish-1',
          title: 'Book',
          deltaYen: -800,
          occurredAt: DateTime(2026, 6, 1, 18),
        ),
      ];

      final pending = filterPendingAdventureBackfills(
        drafts: drafts,
        existingEntryKeys: {
          adventureEntryKey(AdventureEntryType.taskCompleted, 'task-1'),
        },
      );

      expect(pending.map((draft) => draft.sourceId), ['wish-1']);
    });
  });

  group('assignAdventureBackfillBalances', () {
    test(
      'reconstructs balances from current balance when no anchors exist',
      () {
        final balanced = assignAdventureBackfillBalances(
          drafts: [
            AdventureBackfillDraft(
              type: AdventureEntryType.taskCompleted,
              sourceId: 'task-1',
              title: 'Deep work',
              deltaYen: 1500,
              occurredAt: DateTime(2026, 5, 30, 10),
            ),
            AdventureBackfillDraft(
              type: AdventureEntryType.wishPurchased,
              sourceId: 'wish-1',
              title: 'Keyboard',
              deltaYen: -500,
              occurredAt: DateTime(2026, 6, 1, 19),
            ),
          ],
          anchors: const [],
          currentBalanceYen: 3000,
        );

        expect(balanced.length, 2);
        expect(balanced[0].balanceBeforeYen, 2000);
        expect(balanced[0].balanceAfterYen, 3500);
        expect(balanced[1].balanceBeforeYen, 3500);
        expect(balanced[1].balanceAfterYen, 3000);
      },
    );

    test('connects older backfills to the earliest existing ledger anchor', () {
      final balanced = assignAdventureBackfillBalances(
        drafts: [
          AdventureBackfillDraft(
            type: AdventureEntryType.taskCompleted,
            sourceId: 'task-1',
            title: 'Morning task',
            deltaYen: 1000,
            occurredAt: DateTime(2026, 5, 20, 9),
          ),
          AdventureBackfillDraft(
            type: AdventureEntryType.wishPurchased,
            sourceId: 'wish-1',
            title: 'Mug',
            deltaYen: -400,
            occurredAt: DateTime(2026, 5, 21, 21),
          ),
        ],
        anchors: [
          AdventureLedgerAnchor(
            occurredAt: DateTime(2026, 5, 25, 12),
            balanceBeforeYen: 1800,
            balanceAfterYen: 2600,
          ),
        ],
        currentBalanceYen: 2600,
      );

      expect(balanced[0].balanceBeforeYen, 1200);
      expect(balanced[0].balanceAfterYen, 2200);
      expect(balanced[1].balanceBeforeYen, 2200);
      expect(balanced[1].balanceAfterYen, 1800);
    });

    test('keeps continuity when backfills fit between existing anchors', () {
      final balanced = assignAdventureBackfillBalances(
        drafts: [
          AdventureBackfillDraft(
            type: AdventureEntryType.taskCompleted,
            sourceId: 'task-1',
            title: 'Task',
            deltaYen: 500,
            occurredAt: DateTime(2026, 6, 3, 10),
          ),
          AdventureBackfillDraft(
            type: AdventureEntryType.wishPurchased,
            sourceId: 'wish-1',
            title: 'Tea',
            deltaYen: -200,
            occurredAt: DateTime(2026, 6, 3, 20),
          ),
        ],
        anchors: [
          AdventureLedgerAnchor(
            occurredAt: DateTime(2026, 6, 3, 8),
            balanceBeforeYen: 1000,
            balanceAfterYen: 1500,
          ),
          AdventureLedgerAnchor(
            occurredAt: DateTime(2026, 6, 4, 8),
            balanceBeforeYen: 1800,
            balanceAfterYen: 2200,
          ),
        ],
        currentBalanceYen: 2200,
      );

      expect(balanced[0].balanceBeforeYen, 1500);
      expect(balanced[0].balanceAfterYen, 2000);
      expect(balanced[1].balanceBeforeYen, 2000);
      expect(balanced[1].balanceAfterYen, 1800);
    });

    test(
      'allows chartable entries after backfill by giving concrete balances',
      () {
        final balanced = assignAdventureBackfillBalances(
          drafts: [
            AdventureBackfillDraft(
              type: AdventureEntryType.taskCompleted,
              sourceId: 'task-1',
              title: 'Task',
              deltaYen: 900,
              occurredAt: DateTime(2026, 6, 7, 14),
            ),
          ],
          anchors: const [],
          currentBalanceYen: 1900,
        );

        final entry = AdventureLogEntry(
          id: 'entry-1',
          type: balanced.first.type,
          sourceId: balanced.first.sourceId,
          title: balanced.first.title,
          deltaYen: balanced.first.deltaYen,
          balanceBeforeYen: balanced.first.balanceBeforeYen,
          balanceAfterYen: balanced.first.balanceAfterYen,
          occurredAt: balanced.first.occurredAt,
        );

        expect(entry.affectsChart, isTrue);
      },
    );
  });
}
