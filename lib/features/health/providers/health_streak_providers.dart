import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/health/data/health_streak_repository.dart';

final healthStreakRepositoryProvider = Provider<HealthStreakRepository>(
  (_) => HealthStreakRepository(),
);
