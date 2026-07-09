import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/calendar_sync/data/calendar_task_sync_repository.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/features/economy/data/economy_repository.dart';
import 'package:task_manager/features/economy/providers/economy_providers.dart';
import 'package:task_manager/features/roulette/data/roulette_service.dart';
import 'package:task_manager/features/roulette/model/roulette_outcome.dart';
import 'package:task_manager/features/roulette/providers/roulette_providers.dart';
import 'package:task_manager/features/timer/viewmodel/timer_actions.dart';
import 'package:task_manager/features/todo/data/todo_repository.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/models/calendar_task.dart';

class _MockCalendarTaskSyncRepository extends Mock
    implements CalendarTaskSyncRepository {}

class _MockEconomyRepository extends Mock implements EconomyRepository {}

class _MockTodoRepository extends Mock implements TodoRepository {}

class _MockRouletteService extends Mock implements RouletteService {}

/// UserSettingsViewModel はコンストラクタで FirebaseFirestore.instance /
/// FirebaseAuth.instance / FirebaseStorage.instance を即時取得するため、
/// override 用に本物をインスタンス化するには Firebase.initializeApp() 相当の
/// 疎通が最低限必要（実際の通信は発生しない）。ここではプラットフォーム層を
/// 直接差し込む最小限のフェイクで賄う。
class _FakeFirebaseAppPlatform extends FirebaseAppPlatform {
  _FakeFirebaseAppPlatform()
      : super(defaultFirebaseAppName, const FirebaseOptions(
          apiKey: 'fake-api-key',
          appId: 'fake-app-id',
          messagingSenderId: 'fake-sender-id',
          projectId: 'fake-project-id',
          storageBucket: 'fake-project-id.appspot.com',
        ));
}

class _FakeFirebasePlatform extends FirebasePlatform {
  final _app = _FakeFirebaseAppPlatform();

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _app;

  @override
  List<FirebaseAppPlatform> get apps => [_app];

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async => _app;
}

class _FakeUserSettingsNotifier extends UserSettingsViewModel {
  _FakeUserSettingsNotifier(this._settings);
  final UserSettings _settings;

  // isLoading:true にして completeTaskFast() を常にフォールバック経路
  // （economyRepo.completeTask を直接 await する安全な経路）に通す。
  // これらのテストはローカルファースト機能自体の検証対象ではないため、
  // モックの戻り値がそのまま結果に反映されるという既存の前提を保つ。
  @override
  UserSettingsState build() =>
      UserSettingsState(settings: _settings, isLoading: true);
}

void main() {
  setUpAll(() {
    registerFallbackValue(const UserSettings());
    TestWidgetsFlutterBinding.ensureInitialized();
    Firebase.delegatePackingProperty = _FakeFirebasePlatform();
  });

  late _MockCalendarTaskSyncRepository calendarRepo;
  late _MockEconomyRepository economyRepo;
  late _MockTodoRepository todoRepo;
  late _MockRouletteService rouletteService;
  late ProviderContainer container;

  ProviderContainer buildContainer({double hourlyRate = 1000}) {
    return ProviderContainer(
      overrides: [
        calendarTaskSyncRepositoryProvider.overrideWithValue(calendarRepo),
        economyRepositoryProvider.overrideWithValue(economyRepo),
        todoRepositoryProvider.overrideWithValue(todoRepo),
        rouletteServiceProvider.overrideWithValue(rouletteService),
        // completeTaskFast() 経由で PendingTaskCompletionsNotifier.build() が
        // authStateProvider を watch するため、実FirebaseAuthへの接続を避ける
        // ためにoverrideする（値自体はこのテストの検証対象ではない）。
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        userSettingsProvider.overrideWith(
          () => _FakeUserSettingsNotifier(
            UserSettings(monthlyBudget: (hourlyRate * 100).round(), monthlyQuestDays: 20, dailyQuestMinutes: 300),
          ),
        ),
      ],
    );
  }

  setUp(() {
    calendarRepo = _MockCalendarTaskSyncRepository();
    economyRepo = _MockEconomyRepository();
    todoRepo = _MockTodoRepository();
    rouletteService = _MockRouletteService();
    container = buildContainer();
  });

  tearDown(() => container.dispose());

  CalendarTask sampleTask({bool isTodo = false}) {
    final start = DateTime(2026, 7, 6, 9, 0);
    return CalendarTask(
      id: 'task-1',
      title: 'サンプル',
      start: isTodo ? null : start,
      end: isTodo ? null : start.add(const Duration(minutes: 60)),
      rewardYen: 300,
      isTodo: isTodo,
    );
  }

  group('saveProgress', () {
    test('成功時は true を返す', () async {
      when(() => calendarRepo.saveProgress(
            taskId: any(named: 'taskId'),
            predictedMinutes: any(named: 'predictedMinutes'),
            actualMinutes: any(named: 'actualMinutes'),
          )).thenAnswer((_) async {});

      final actions = container.read(timerActionsProvider);
      final ok = await actions.saveProgress(
        taskId: 'task-1',
        predictedMinutes: 60,
        actualMinutes: 20,
      );

      expect(ok, isTrue);
      verify(() => calendarRepo.saveProgress(
            taskId: 'task-1',
            predictedMinutes: 60,
            actualMinutes: 20,
          )).called(1);
    });

    test('タスク削除済み等の例外は握って false を返す', () async {
      when(() => calendarRepo.saveProgress(
            taskId: any(named: 'taskId'),
            predictedMinutes: any(named: 'predictedMinutes'),
            actualMinutes: any(named: 'actualMinutes'),
          )).thenThrow(Exception('not-found'));

      final actions = container.read(timerActionsProvider);
      final ok = await actions.saveProgress(
        taskId: 'task-1',
        predictedMinutes: 60,
        actualMinutes: 20,
      );

      expect(ok, isFalse);
    });
  });

  group('complete', () {
    test('カレンダータスクは convertToCalendarEvent を呼ばず moveTaskById で実績ベースに再配置する',
        () async {
      when(() => calendarRepo.moveTaskById(
            taskId: any(named: 'taskId'),
            newStart: any(named: 'newStart'),
            newEnd: any(named: 'newEnd'),
          )).thenAnswer((_) async {});
      when(() => economyRepo.completeTask(
            taskId: any(named: 'taskId'),
            title: any(named: 'title'),
            rewardYen: any(named: 'rewardYen'),
            predictedMinutes: any(named: 'predictedMinutes'),
            actualMinutes: any(named: 'actualMinutes'),
          )).thenAnswer((_) async => const BalanceLedgerResult(
            applied: true,
            deltaYen: 1000,
            balanceBeforeYen: 0,
            balanceAfterYen: 1000,
            cumulativeTaskCountBefore: 0,
            cumulativeTaskCountAfter: 1,
          ));
      when(() => rouletteService.spin(
            completionId: any(named: 'completionId'),
            settings: any(named: 'settings'),
          )).thenAnswer((_) async => const RouletteOutcome.invalidConfig());

      final before = DateTime.now();
      final actions = container.read(timerActionsProvider);
      final result = await actions.complete(
        task: sampleTask(),
        predictedMinutes: 60,
        actualMinutes: 45,
      );
      final after = DateTime.now();

      expect(result, isNotNull);
      expect(result!.balanceAfterYen, 1000);
      verifyNever(() => todoRepo.convertToCalendarEvent(
            taskId: any(named: 'taskId'),
            start: any(named: 'start'),
            end: any(named: 'end'),
          ));
      final captured = verify(() => calendarRepo.moveTaskById(
            taskId: 'task-1',
            newStart: captureAny(named: 'newStart'),
            newEnd: captureAny(named: 'newEnd'),
          )).captured;
      final capturedStart = captured[0] as DateTime;
      final capturedEnd = captured[1] as DateTime;
      expect(
        capturedStart.isAfter(before.subtract(const Duration(minutes: 46))),
        isTrue,
      );
      expect(
        capturedStart.isBefore(after.subtract(const Duration(minutes: 44))),
        isTrue,
      );
      expect(capturedEnd.isAfter(before), isTrue);
      expect(capturedEnd.isBefore(after.add(const Duration(seconds: 1))),
          isTrue);
    });

    test('ToDoタスクは completeTask 前に convertToCalendarEvent を呼ぶ', () async {
      final callOrder = <String>[];
      when(() => todoRepo.convertToCalendarEvent(
            taskId: any(named: 'taskId'),
            start: any(named: 'start'),
            end: any(named: 'end'),
          )).thenAnswer((_) async {
        callOrder.add('convert');
      });
      when(() => economyRepo.completeTask(
            taskId: any(named: 'taskId'),
            title: any(named: 'title'),
            rewardYen: any(named: 'rewardYen'),
            predictedMinutes: any(named: 'predictedMinutes'),
            actualMinutes: any(named: 'actualMinutes'),
          )).thenAnswer((_) async {
        callOrder.add('complete');
        return const BalanceLedgerResult(
          applied: true,
          deltaYen: 500,
          balanceBeforeYen: 0,
          balanceAfterYen: 500,
          cumulativeTaskCountBefore: 0,
          cumulativeTaskCountAfter: 1,
        );
      });
      when(() => rouletteService.spin(
            completionId: any(named: 'completionId'),
            settings: any(named: 'settings'),
          )).thenAnswer((_) async => const RouletteOutcome.invalidConfig());

      final actions = container.read(timerActionsProvider);
      final result = await actions.complete(
        task: sampleTask(isTodo: true),
        predictedMinutes: 30,
        actualMinutes: 25,
      );

      expect(result, isNotNull);
      expect(callOrder, ['convert', 'complete']);
    });

    test('completeTask が applied=false のとき null を返す', () async {
      when(() => economyRepo.completeTask(
            taskId: any(named: 'taskId'),
            title: any(named: 'title'),
            rewardYen: any(named: 'rewardYen'),
            predictedMinutes: any(named: 'predictedMinutes'),
            actualMinutes: any(named: 'actualMinutes'),
          )).thenAnswer((_) async => const BalanceLedgerResult(
            applied: false,
            deltaYen: 0,
            balanceBeforeYen: 0,
            balanceAfterYen: 0,
          ));

      final actions = container.read(timerActionsProvider);
      final result = await actions.complete(
        task: sampleTask(),
        predictedMinutes: 60,
        actualMinutes: 45,
      );

      expect(result, isNull);
    });

    test('例外発生時は null を返す', () async {
      when(() => economyRepo.completeTask(
            taskId: any(named: 'taskId'),
            title: any(named: 'title'),
            rewardYen: any(named: 'rewardYen'),
            predictedMinutes: any(named: 'predictedMinutes'),
            actualMinutes: any(named: 'actualMinutes'),
          )).thenThrow(Exception('boom'));

      final actions = container.read(timerActionsProvider);
      final result = await actions.complete(
        task: sampleTask(),
        predictedMinutes: 60,
        actualMinutes: 45,
      );

      expect(result, isNull);
    });
  });

  group('placeForCompletion', () {
    test('時間指定タスク：moveTaskById が (now-actual, now) で呼ばれ自idと predictedOverride=null を返す',
        () async {
      when(() => calendarRepo.moveTaskById(
            taskId: any(named: 'taskId'),
            newStart: any(named: 'newStart'),
            newEnd: any(named: 'newEnd'),
          )).thenAnswer((_) async {});

      final before = DateTime.now();
      final actions = container.read(timerActionsProvider);
      final result = await actions.placeForCompletion(
        taskId: 'task-1',
        isTodo: false,
        isAllDay: false,
        title: 'サンプル',
        minutesForPlacement: 30,
      );
      final after = DateTime.now();

      expect(result.taskId, 'task-1');
      expect(result.predictedOverride, isNull);
      final captured = verify(() => calendarRepo.moveTaskById(
            taskId: 'task-1',
            newStart: captureAny(named: 'newStart'),
            newEnd: captureAny(named: 'newEnd'),
          )).captured;
      final capturedStart = captured[0] as DateTime;
      final capturedEnd = captured[1] as DateTime;
      expect(
        capturedStart.isAfter(before.subtract(const Duration(minutes: 31))),
        isTrue,
      );
      expect(
        capturedStart.isBefore(after.subtract(const Duration(minutes: 29))),
        isTrue,
      );
      expect(capturedEnd.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(capturedEnd.isBefore(after.add(const Duration(seconds: 1))),
          isTrue);
      verifyNever(() => calendarRepo.createTaskFull(
            title: any(named: 'title'),
            start: any(named: 'start'),
            end: any(named: 'end'),
          ));
      verifyNever(() => todoRepo.convertToCalendarEvent(
            taskId: any(named: 'taskId'),
            start: any(named: 'start'),
            end: any(named: 'end'),
          ));
    });

    test('終日：createTaskFull が (now-actual, now) で呼ばれ新idと predictedOverride=0 を返す',
        () async {
      when(() => calendarRepo.createTaskFull(
            title: any(named: 'title'),
            start: any(named: 'start'),
            end: any(named: 'end'),
            colorId: any(named: 'colorId'),
          )).thenAnswer((_) async => 'new-block-id');

      final before = DateTime.now();
      final actions = container.read(timerActionsProvider);
      final result = await actions.placeForCompletion(
        taskId: 'task-1',
        isTodo: false,
        isAllDay: true,
        title: 'サンプル',
        minutesForPlacement: 40,
      );
      final after = DateTime.now();

      expect(result.taskId, 'new-block-id');
      expect(result.predictedOverride, 0);
      final captured = verify(() => calendarRepo.createTaskFull(
            title: 'サンプル',
            start: captureAny(named: 'start'),
            end: captureAny(named: 'end'),
            colorId: any(named: 'colorId'),
          )).captured;
      final capturedStart = captured[0] as DateTime;
      final capturedEnd = captured[1] as DateTime;
      expect(
        capturedStart.isAfter(before.subtract(const Duration(minutes: 41))),
        isTrue,
      );
      expect(capturedEnd.isBefore(after.add(const Duration(seconds: 1))),
          isTrue);
      verifyNever(() => calendarRepo.moveTaskById(
            taskId: any(named: 'taskId'),
            newStart: any(named: 'newStart'),
            newEnd: any(named: 'newEnd'),
          ));
    });

    test('ToDo：todoRepository.convertToCalendarEvent が呼ばれ自idと predictedOverride=null を返す',
        () async {
      when(() => todoRepo.convertToCalendarEvent(
            taskId: any(named: 'taskId'),
            start: any(named: 'start'),
            end: any(named: 'end'),
          )).thenAnswer((_) async {});

      final actions = container.read(timerActionsProvider);
      final result = await actions.placeForCompletion(
        taskId: 'task-1',
        isTodo: true,
        isAllDay: false,
        title: 'サンプル',
        minutesForPlacement: 20,
      );

      expect(result.taskId, 'task-1');
      expect(result.predictedOverride, isNull);
      verify(() => todoRepo.convertToCalendarEvent(
            taskId: 'task-1',
            start: any(named: 'start'),
            end: any(named: 'end'),
          )).called(1);
    });

    test('日またぎ：開始が完了日0:00に丸められる（分数は保持し表示位置のみ丸め）', () async {
      when(() => calendarRepo.moveTaskById(
            taskId: any(named: 'taskId'),
            newStart: any(named: 'newStart'),
            newEnd: any(named: 'newEnd'),
          )).thenAnswer((_) async {});

      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      // 現在時刻から日付境界(0:00)までの分数より大きい実績分を与え、
      // 開始が前日側にはみ出す状況を作る。
      final minutesForPlacement = now.difference(dayStart).inMinutes + 120;

      final actions = container.read(timerActionsProvider);
      final result = await actions.placeForCompletion(
        taskId: 'task-1',
        isTodo: false,
        isAllDay: false,
        title: 'サンプル',
        minutesForPlacement: minutesForPlacement,
      );

      expect(result.taskId, 'task-1');
      final captured = verify(() => calendarRepo.moveTaskById(
            taskId: 'task-1',
            newStart: captureAny(named: 'newStart'),
            newEnd: captureAny(named: 'newEnd'),
          )).captured;
      final capturedStart = captured[0] as DateTime;
      expect(capturedStart, DateTime(now.year, now.month, now.day));
    });
  });
}
