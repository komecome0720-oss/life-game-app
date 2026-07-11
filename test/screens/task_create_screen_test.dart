import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:task_manager/features/calendar_sync/providers/calendar_sync_providers.dart';
import 'package:task_manager/features/calendar_sync/viewmodel/calendar_sync_viewmodel.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/screens/task_create_screen.dart';

/// UserSettingsViewModel はコンストラクタで FirebaseFirestore.instance /
/// FirebaseAuth.instance / FirebaseStorage.instance を即時取得するため、
/// override 用に本物をインスタンス化するには Firebase.initializeApp() 相当の
/// 疎通が最低限必要（実際の通信は発生しない）。quick_create_sheet_test.dart と
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

/// デフォルト設定（predictionChipMinutes = [15,30,45,60,90,120,180]）を返すフェイク。
class _FakeUserSettingsNotifier extends UserSettingsViewModel {
  @override
  UserSettingsState build() => const UserSettingsState();
}

/// saveNewTask 呼び出しの引数を捕捉するフェイク。CalendarSyncViewModel.build() は
/// Firebase へアクセスしないため、そのまま Notifier として override できる。
class _FakeCalendarSyncViewModel extends CalendarSyncViewModel {
  Map<String, Object?>? captured;
  bool succeed = true;

  @override
  Future<bool> saveNewTask({
    required String title,
    required DateTime start,
    required DateTime end,
    bool isAllDay = false,
    String? description,
    String? location,
    String? colorId,
    List<String>? recurrence,
    bool urgency = true,
    bool importance = true,
    int? estimatedMinutes,
    bool predictionDeclared = false,
  }) async {
    captured = {
      'title': title,
      'start': start,
      'end': end,
      'isAllDay': isAllDay,
      'description': description,
      'location': location,
      'colorId': colorId,
      'recurrence': recurrence,
      'urgency': urgency,
      'importance': importance,
      'estimatedMinutes': estimatedMinutes,
      'predictionDeclared': predictionDeclared,
    };
    return succeed;
  }
}

Future<_FakeCalendarSyncViewModel> _pumpHarness(WidgetTester tester) async {
  final fake = _FakeCalendarSyncViewModel();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userSettingsProvider.overrideWith(_FakeUserSettingsNotifier.new),
        calendarSyncViewModelProvider.overrideWith(() => fake),
      ],
      child: const MaterialApp(
        home: TaskCreateScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Firebase.delegatePackingProperty = _FakeFirebasePlatform();
    await initializeDateFormatting('ja_JP');
  });

  group('TaskCreateScreen', () {
    testWidgets('タイトル未入力では保存できない', (tester) async {
      final fake = await _pumpHarness(tester);

      final saveButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '保存'),
      );
      expect(saveButton.onPressed, isNull);
      expect(fake.captured, isNull);
    });

    testWidgets('終日OFFでは予測時間チップが表示され、ONでは終了日ピッカーに切り替わる', (tester) async {
      await _pumpHarness(tester);

      expect(find.text('予測時間（終了時刻はこれで決まります）'), findsOneWidget);
      expect(find.text('30分'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('予測時間（終了時刻はこれで決まります）'), findsNothing);
      expect(find.text('終了'), findsOneWidget);
    });

    testWidgets('領域セレクターが表示され選択できる', (tester) async {
      await _pumpHarness(tester);

      expect(find.text('領域'), findsOneWidget);
      expect(find.text('×緊急・×重要'), findsOneWidget);

      await tester.tap(find.text('×緊急・×重要'));
      await tester.pump();
      // 選択状態のチェックマークが表示される
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('保存時にsaveNewTaskが正しい引数（colorId=null含む）で呼ばれる', (tester) async {
      final fake = await _pumpHarness(tester);

      await tester.enterText(find.byType(TextFormField).first, '資料整理');
      await tester.tap(find.text('×緊急・×重要'));
      await tester.pump();
      await tester.tap(find.text('45分'));
      await tester.pump();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(fake.captured, isNotNull);
      expect(fake.captured!['title'], '資料整理');
      expect(fake.captured!['colorId'], isNull);
      expect(fake.captured!['urgency'], false);
      expect(fake.captured!['importance'], false);
      expect(fake.captured!['estimatedMinutes'], 45);
      expect(fake.captured!['predictionDeclared'], true);
      expect(fake.captured!['isAllDay'], false);
    });

    testWidgets('終日ONで保存するとpredictionDeclared=false・estimatedMinutes=nullで呼ばれる',
        (tester) async {
      final fake = await _pumpHarness(tester);

      await tester.enterText(find.byType(TextFormField).first, '旅行');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(fake.captured, isNotNull);
      expect(fake.captured!['isAllDay'], true);
      expect(fake.captured!['estimatedMinutes'], isNull);
      expect(fake.captured!['predictionDeclared'], false);
    });
  });
}
