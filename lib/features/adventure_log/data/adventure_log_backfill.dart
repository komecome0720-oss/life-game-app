import 'package:task_manager/features/adventure_log/model/adventure_log_entry.dart';

String adventureEntryKey(AdventureEntryType type, String sourceId) {
  return '${type.wireName}:$sourceId';
}

class AdventureBackfillDraft {
  const AdventureBackfillDraft({
    required this.type,
    required this.sourceId,
    required this.title,
    required this.deltaYen,
    required this.occurredAt,
    this.note,
  });

  final AdventureEntryType type;
  final String sourceId;
  final String title;
  final int deltaYen;
  final DateTime occurredAt;
  final String? note;

  String get entryKey => adventureEntryKey(type, sourceId);
}

class AdventureBackfillBalancedDraft extends AdventureBackfillDraft {
  const AdventureBackfillBalancedDraft({
    required super.type,
    required super.sourceId,
    required super.title,
    required super.deltaYen,
    required super.occurredAt,
    required this.balanceBeforeYen,
    required this.balanceAfterYen,
    super.note,
  });

  final int balanceBeforeYen;
  final int balanceAfterYen;
}

class AdventureLedgerAnchor {
  const AdventureLedgerAnchor({
    required this.occurredAt,
    required this.balanceBeforeYen,
    required this.balanceAfterYen,
  });

  final DateTime occurredAt;
  final int balanceBeforeYen;
  final int balanceAfterYen;
}

List<AdventureBackfillDraft> filterPendingAdventureBackfills({
  required List<AdventureBackfillDraft> drafts,
  required Set<String> existingEntryKeys,
}) {
  return drafts
      .where((draft) => !existingEntryKeys.contains(draft.entryKey))
      .toList();
}

List<AdventureBackfillBalancedDraft> assignAdventureBackfillBalances({
  required List<AdventureBackfillDraft> drafts,
  required List<AdventureLedgerAnchor> anchors,
  required int currentBalanceYen,
}) {
  if (drafts.isEmpty) return const [];

  final sortedDrafts = [...drafts]..sort(_compareByOccurredAt);
  final sortedAnchors = [...anchors]
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

  if (sortedAnchors.isEmpty) {
    final startBalance =
        currentBalanceYen -
        sortedDrafts.fold<int>(0, (sum, draft) => sum + draft.deltaYen);
    return _assignForward(sortedDrafts, startBalance);
  }

  final balanced = <AdventureBackfillBalancedDraft>[];
  var draftIndex = 0;

  final beforeFirst = <AdventureBackfillDraft>[];
  while (draftIndex < sortedDrafts.length &&
      sortedDrafts[draftIndex].occurredAt.isBefore(
        sortedAnchors.first.occurredAt,
      )) {
    beforeFirst.add(sortedDrafts[draftIndex]);
    draftIndex++;
  }
  balanced.addAll(
    _assignBackward(beforeFirst, sortedAnchors.first.balanceBeforeYen),
  );

  for (var i = 0; i < sortedAnchors.length - 1; i++) {
    final startAnchor = sortedAnchors[i];
    final endAnchor = sortedAnchors[i + 1];
    final between = <AdventureBackfillDraft>[];
    while (draftIndex < sortedDrafts.length &&
        !sortedDrafts[draftIndex].occurredAt.isAfter(endAnchor.occurredAt)) {
      between.add(sortedDrafts[draftIndex]);
      draftIndex++;
    }
    if (between.isEmpty) continue;

    final expectedEnd =
        startAnchor.balanceAfterYen +
        between.fold(0, (sum, draft) => sum + draft.deltaYen);
    if (expectedEnd == endAnchor.balanceBeforeYen) {
      balanced.addAll(_assignForward(between, startAnchor.balanceAfterYen));
    } else {
      balanced.addAll(_assignBackward(between, endAnchor.balanceBeforeYen));
    }
  }

  final afterLast = <AdventureBackfillDraft>[
    for (; draftIndex < sortedDrafts.length; draftIndex++)
      sortedDrafts[draftIndex],
  ];
  balanced.addAll(
    _assignForward(afterLast, sortedAnchors.last.balanceAfterYen),
  );

  balanced.sort(_compareBalancedByOccurredAt);
  return balanced;
}

List<AdventureBackfillBalancedDraft> _assignForward(
  List<AdventureBackfillDraft> drafts,
  int startBalance,
) {
  final balanced = <AdventureBackfillBalancedDraft>[];
  var balance = startBalance;
  for (final draft in drafts) {
    final before = balance;
    final after = before + draft.deltaYen;
    balanced.add(
      AdventureBackfillBalancedDraft(
        type: draft.type,
        sourceId: draft.sourceId,
        title: draft.title,
        deltaYen: draft.deltaYen,
        occurredAt: draft.occurredAt,
        balanceBeforeYen: before,
        balanceAfterYen: after,
        note: draft.note,
      ),
    );
    balance = after;
  }
  return balanced;
}

List<AdventureBackfillBalancedDraft> _assignBackward(
  List<AdventureBackfillDraft> drafts,
  int endBalance,
) {
  if (drafts.isEmpty) return const [];

  final balanced = <AdventureBackfillBalancedDraft>[];
  var balance = endBalance;
  for (final draft in drafts.reversed) {
    final after = balance;
    final before = after - draft.deltaYen;
    balanced.add(
      AdventureBackfillBalancedDraft(
        type: draft.type,
        sourceId: draft.sourceId,
        title: draft.title,
        deltaYen: draft.deltaYen,
        occurredAt: draft.occurredAt,
        balanceBeforeYen: before,
        balanceAfterYen: after,
        note: draft.note,
      ),
    );
    balance = before;
  }
  balanced.sort(_compareBalancedByOccurredAt);
  return balanced;
}

int _compareByOccurredAt(AdventureBackfillDraft a, AdventureBackfillDraft b) {
  final compared = a.occurredAt.compareTo(b.occurredAt);
  if (compared != 0) return compared;
  final typeCompared = a.type.index.compareTo(b.type.index);
  if (typeCompared != 0) return typeCompared;
  return a.sourceId.compareTo(b.sourceId);
}

int _compareBalancedByOccurredAt(
  AdventureBackfillBalancedDraft a,
  AdventureBackfillBalancedDraft b,
) {
  return _compareByOccurredAt(a, b);
}
