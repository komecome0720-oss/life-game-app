import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/economy/data/economy_repository.dart';
import 'package:task_manager/features/economy/providers/economy_providers.dart';
import 'package:task_manager/features/economy/viewmodel/economy_fast_complete_service.dart';
import 'package:task_manager/features/economy/viewmodel/pending_task_completions_notifier.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';

class _MockEconomyRepository extends Mock implements EconomyRepository {}

class _MockUser extends Mock implements User {}

/// UserSettingsViewModel はコンストラクタで FirebaseFirestore.instance /
/// FirebaseAuth.instance / FirebaseStorage.instance を即時取得するため、
/// override 用に本物をインスタンス化するには Firebase.initializeApp() 相当の
/// 疎通が最低限必要（実際の通信は発生しない）。timer_actions_test.dart と
/// 同じ最小限のフェイクで賄う。
class _FakeFirebaseAppPlatform extends FirebaseAppPlatform {
  _FakeFirebaseAppPlatform()
      : super(
          defaultFirebaseAppName,
          const FirebaseOptions(
            apiKey: 'fake-api-key',
            appId: 'fake-app-id',
            messagingSenderId: 'fake-sender-id',
            projectId: 'fake-project-id',
            storageBucket: 'fake-project-id.appspot.com',
          ),
        );
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

/// テストから任意の [UserSettingsState] を注入できるフェイク。
class _FakeUserSettingsNotifier extends UserSettingsViewModel {
  _FakeUserSettingsNotifier(this._initial);
  final UserSettingsState _initial;

  @override
  UserSettingsState build() => _initial;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Firebase.delegatePackingProperty = _FakeFirebasePlatform();
  });

  late _MockEconomyRepository economyRepo;
  late ProviderContainer container;
  late StreamController<User?> authController;

  ProviderContainer buildContainer(UserSettingsState initialSettingsState) {
    authController = StreamController<User?>.broadcast();
    return ProviderContainer(
      overrides: [
        economyRepositoryProvider.overrideWithValue(economyRepo),
        authStateProvider.overrideWith((ref) => authController.stream),
        userSettingsProvider.overrideWith(
          () => _FakeUserSettingsNotifier(initialSettingsState),
        ),
      ],
    );
  }

  setUp(() {
    economyRepo = _MockEconomyRepository();
  });

  tearDown(() async {
    container.dispose();
    await authController.close();
  });

  const taskId = 'task-1';
  const title = 'サンプル';
  const rewardYen = 300;

  test('isLoading:true のときは repo.completeTask を直接awaitしその戻り値をそのまま返す', () async {
    container = buildContainer(const UserSettingsState(isLoading: true));

    const repoResult = BalanceLedgerResult(
      applied: true,
      deltaYen: rewardYen,
      balanceBeforeYen: 999,
      balanceAfterYen: 999 + rewardYen,
      cumulativeTaskCountBefore: 7,
      cumulativeTaskCountAfter: 8,
    );
    when(
      () => economyRepo.completeTask(
        taskId: any(named: 'taskId'),
        title: any(named: 'title'),
        rewardYen: any(named: 'rewardYen'),
        predictedMinutes: any(named: 'predictedMinutes'),
        actualMinutes: any(named: 'actualMinutes'),
      ),
    ).thenAnswer((_) async => repoResult);

    final service = container.read(economyFastCompleteServiceProvider);
    final result = await service.completeTaskFast(
      taskId: taskId,
      title: title,
      rewardYen: rewardYen,
      predictedMinutes: 30,
      actualMinutes: 25,
    );

    expect(result.applied, isTrue);
    expect(result.balanceBeforeYen, 999);
    expect(result.balanceAfterYen, 999 + rewardYen);
    expect(result.cumulativeTaskCountBefore, 7);
    expect(result.cumulativeTaskCountAfter, 8);
    verify(
      () => economyRepo.completeTask(
        taskId: taskId,
        title: title,
        rewardYen: rewardYen,
        predictedMinutes: 30,
        actualMinutes: 25,
      ),
    ).called(1);
  });

  test(
    'isLoading:false かつキャッシュがあるときはFirestore書き込み完了を待たずに仮値を返す',
    () async {
      container = buildContainer(
        const UserSettingsState(
          settings: UserSettings(totalEarned: 1000, cumulativeTaskCount: 3),
        ),
      );

      final completer = Completer<BalanceLedgerResult>();
      when(
        () => economyRepo.completeTask(
          taskId: any(named: 'taskId'),
          title: any(named: 'title'),
          rewardYen: any(named: 'rewardYen'),
          predictedMinutes: any(named: 'predictedMinutes'),
          actualMinutes: any(named: 'actualMinutes'),
        ),
      ).thenAnswer((_) => completer.future);

      final service = container.read(economyFastCompleteServiceProvider);
      final result = await service.completeTaskFast(
        taskId: taskId,
        title: title,
        rewardYen: rewardYen,
        predictedMinutes: 30,
        actualMinutes: 25,
      );

      // repo.completeTask の Future はまだ未解決だが、completeTaskFast は
      // それを待たずにキャッシュ由来の仮値を返す。
      expect(completer.isCompleted, isFalse);
      expect(result.applied, isTrue);
      expect(result.balanceBeforeYen, 1000);
      expect(result.balanceAfterYen, 1000 + rewardYen);
      expect(result.cumulativeTaskCountBefore, 3);
      expect(result.cumulativeTaskCountAfter, 4);

      completer.complete(
        const BalanceLedgerResult(
          applied: true,
          deltaYen: rewardYen,
          balanceBeforeYen: 1000,
          balanceAfterYen: 1000 + rewardYen,
          cumulativeTaskCountBefore: 3,
          cumulativeTaskCountAfter: 4,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('同一taskIdが処理中（in-flight）のうちに2回目を呼ぶと即 applied:false を返す', () async {
    container = buildContainer(
      const UserSettingsState(
        settings: UserSettings(totalEarned: 1000, cumulativeTaskCount: 3),
      ),
    );

    final completer = Completer<BalanceLedgerResult>();
    when(
      () => economyRepo.completeTask(
        taskId: any(named: 'taskId'),
        title: any(named: 'title'),
        rewardYen: any(named: 'rewardYen'),
        predictedMinutes: any(named: 'predictedMinutes'),
        actualMinutes: any(named: 'actualMinutes'),
      ),
    ).thenAnswer((_) => completer.future);

    final service = container.read(economyFastCompleteServiceProvider);
    final first = await service.completeTaskFast(
      taskId: taskId,
      title: title,
      rewardYen: rewardYen,
      predictedMinutes: 30,
      actualMinutes: 25,
    );
    expect(first.applied, isTrue);

    final second = await service.completeTaskFast(
      taskId: taskId,
      title: title,
      rewardYen: rewardYen,
      predictedMinutes: 30,
      actualMinutes: 25,
    );
    expect(second.applied, isFalse);

    completer.complete(
      const BalanceLedgerResult(
        applied: true,
        deltaYen: rewardYen,
        balanceBeforeYen: 1000,
        balanceAfterYen: 1000 + rewardYen,
        cumulativeTaskCountBefore: 3,
        cumulativeTaskCountAfter: 4,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  });

  test('異なる2つのtaskIdを連続完了すると、2件目のbeforeに1件目のpendingDeltaが加算される', () async {
    container = buildContainer(
      const UserSettingsState(
        settings: UserSettings(totalEarned: 1000, cumulativeTaskCount: 3),
      ),
    );

    final completerA = Completer<BalanceLedgerResult>();
    when(
      () => economyRepo.completeTask(
        taskId: 'task-a',
        title: any(named: 'title'),
        rewardYen: any(named: 'rewardYen'),
        predictedMinutes: any(named: 'predictedMinutes'),
        actualMinutes: any(named: 'actualMinutes'),
      ),
    ).thenAnswer((_) => completerA.future);
    when(
      () => economyRepo.completeTask(
        taskId: 'task-b',
        title: any(named: 'title'),
        rewardYen: any(named: 'rewardYen'),
        predictedMinutes: any(named: 'predictedMinutes'),
        actualMinutes: any(named: 'actualMinutes'),
      ),
    ).thenAnswer((_) async => const BalanceLedgerResult(
          applied: true,
          deltaYen: 200,
          balanceBeforeYen: 0,
          balanceAfterYen: 0,
        ));

    final service = container.read(economyFastCompleteServiceProvider);
    final resultA = await service.completeTaskFast(
      taskId: 'task-a',
      title: 'A',
      rewardYen: 300,
      predictedMinutes: 30,
      actualMinutes: 25,
    );
    expect(resultA.balanceBeforeYen, 1000);
    expect(resultA.balanceAfterYen, 1300);

    final resultB = await service.completeTaskFast(
      taskId: 'task-b',
      title: 'B',
      rewardYen: 200,
      predictedMinutes: 30,
      actualMinutes: 25,
    );
    // Aの裏処理がまだ確定していない（pendingDeltaYen=300が残っている）ため、
    // Bのbeforeにはそれが加算される。
    expect(resultB.balanceBeforeYen, 1300);
    expect(resultB.balanceAfterYen, 1500);
    expect(resultB.cumulativeTaskCountBefore, 4);
    expect(resultB.cumulativeTaskCountAfter, 5);

    completerA.complete(
      const BalanceLedgerResult(
        applied: true,
        deltaYen: 300,
        balanceBeforeYen: 1000,
        balanceAfterYen: 1300,
        cumulativeTaskCountBefore: 3,
        cumulativeTaskCountAfter: 4,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  });

  test(
    '背後のcompleteTaskがapplied:falseまたは例外を返してもin-flight集合からtaskIdが除去される',
    () async {
      container = buildContainer(
        const UserSettingsState(
          settings: UserSettings(totalEarned: 1000, cumulativeTaskCount: 3),
        ),
      );

      final completer = Completer<BalanceLedgerResult>();
      when(
        () => economyRepo.completeTask(
          taskId: any(named: 'taskId'),
          title: any(named: 'title'),
          rewardYen: any(named: 'rewardYen'),
          predictedMinutes: any(named: 'predictedMinutes'),
          actualMinutes: any(named: 'actualMinutes'),
        ),
      ).thenAnswer((_) => completer.future);

      final service = container.read(economyFastCompleteServiceProvider);
      await service.completeTaskFast(
        taskId: taskId,
        title: title,
        rewardYen: rewardYen,
        predictedMinutes: 30,
        actualMinutes: 25,
      );

      final notifier = container.read(pendingTaskCompletionsProvider.notifier);
      expect(notifier.isInFlight(taskId), isTrue);

      completer.complete(
        const BalanceLedgerResult(
          applied: false,
          deltaYen: 0,
          balanceBeforeYen: 1000,
          balanceAfterYen: 1000,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(notifier.isInFlight(taskId), isFalse);
    },
  );

  test('例外を投げた場合もin-flight集合からtaskIdが除去される', () async {
    container = buildContainer(
      const UserSettingsState(
        settings: UserSettings(totalEarned: 1000, cumulativeTaskCount: 3),
      ),
    );

    final completer = Completer<BalanceLedgerResult>();
    when(
      () => economyRepo.completeTask(
        taskId: any(named: 'taskId'),
        title: any(named: 'title'),
        rewardYen: any(named: 'rewardYen'),
        predictedMinutes: any(named: 'predictedMinutes'),
        actualMinutes: any(named: 'actualMinutes'),
      ),
    ).thenAnswer((_) => completer.future);

    final service = container.read(economyFastCompleteServiceProvider);
    await service.completeTaskFast(
      taskId: taskId,
      title: title,
      rewardYen: rewardYen,
      predictedMinutes: 30,
      actualMinutes: 25,
    );

    final notifier = container.read(pendingTaskCompletionsProvider.notifier);
    expect(notifier.isInFlight(taskId), isTrue);

    completer.completeError(Exception('boom'));
    await Future<void>.delayed(Duration.zero);

    expect(notifier.isInFlight(taskId), isFalse);
  });

  test('authStateProviderのuidが変わるとpendingTaskCompletionsProviderの状態がリセットされる', () async {
    container = buildContainer(
      const UserSettingsState(
        settings: UserSettings(totalEarned: 1000, cumulativeTaskCount: 3),
      ),
    );

    final userA = _MockUser();
    when(() => userA.uid).thenReturn('uid-a');
    final userB = _MockUser();
    when(() => userB.uid).thenReturn('uid-b');

    // 実際の画面と同様に常時listenしておく（未listenだと更新の伝播が
    // 遅延・省略されうるため、テストでも同じ条件を作る）。
    final sub = container.listen(pendingTaskCompletionsProvider, (_, _) {});
    addTearDown(sub.close);

    authController.add(userA);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final notifier = container.read(pendingTaskCompletionsProvider.notifier);
    notifier.begin(taskId, deltaYen: rewardYen, deltaCount: 1);
    expect(notifier.isInFlight(taskId), isTrue);

    authController.add(userB);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      container.read(pendingTaskCompletionsProvider).inFlightTaskIds,
      isEmpty,
    );
  });

  test('navigatorKey.currentStateが未アタッチ（テスト環境でnull）でも例外を投げない', () async {
    container = buildContainer(
      const UserSettingsState(
        settings: UserSettings(totalEarned: 1000, cumulativeTaskCount: 3),
      ),
    );

    when(
      () => economyRepo.completeTask(
        taskId: any(named: 'taskId'),
        title: any(named: 'title'),
        rewardYen: any(named: 'rewardYen'),
        predictedMinutes: any(named: 'predictedMinutes'),
        actualMinutes: any(named: 'actualMinutes'),
      ),
    ).thenAnswer((_) async => const BalanceLedgerResult(
          applied: false,
          deltaYen: 0,
          balanceBeforeYen: 0,
          balanceAfterYen: 0,
        ));

    final service = container.read(economyFastCompleteServiceProvider);
    // navigatorKey は main.dart 側でのみアタッチされ、このテストでは未アタッチ
    // (currentState == null) のまま。_notifyFailure が例外を投げないことを確認する。
    await service.completeTaskFast(
      taskId: taskId,
      title: title,
      rewardYen: rewardYen,
      predictedMinutes: 30,
      actualMinutes: 25,
    );
    await Future<void>.delayed(Duration.zero);
  });
}
