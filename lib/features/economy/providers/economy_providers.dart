import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/economy/data/economy_repository.dart';

final economyRepositoryProvider = Provider<EconomyRepository>(
  (_) => EconomyRepository(),
);
