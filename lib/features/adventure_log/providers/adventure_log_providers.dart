import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/adventure_log/data/adventure_log_repository.dart';
import 'package:task_manager/features/adventure_log/model/adventure_log_entry.dart';

final adventureLogRepositoryProvider = Provider<AdventureLogRepository>(
  (_) => AdventureLogRepository(),
);

final adventureLogEntriesProvider =
    StreamProvider.autoDispose<List<AdventureLogEntry>>((ref) {
      return ref.watch(adventureLogRepositoryProvider).watchEntries();
    });

final adventureLogBackfillProvider = FutureProvider<void>((ref) async {
  await ref
      .watch(adventureLogRepositoryProvider)
      .backfillLegacyEntriesIfNeeded();
});
