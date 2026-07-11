import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/widgets/quick_create_sheet.dart';

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

/// デフォルト設定（predictionChipMinutes = [15,30,45,60,90,120,180]）を返すフェイク。
class _FakeUserSettingsNotifier extends UserSettingsViewModel {
  @override
  UserSettingsState build() => const UserSettingsState();
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required ValueChanged<QuickCreateResult?> onResult,
  DateTime? initialStart,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userSettingsProvider.overrideWith(_FakeUserSettingsNotifier.new),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final result = await showModalBottomSheet<QuickCreateResult>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => QuickCreateSheet(
                    initialStart: initialStart ?? DateTime(2026, 6, 23, 20, 15),
                  ),
                );
                onResult(result);
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Firebase.delegatePackingProperty = _FakeFirebasePlatform();
    await initializeDateFormatting('ja_JP');
  });

  group('QuickCreateSheet', () {
    testWidgets('タイトルと日時の間に領域セレクターを表示する', (tester) async {
      await _pumpHarness(tester, onResult: (_) {});

      expect(find.text('予定を追加'), findsOneWidget);
      expect(find.text('領域'), findsOneWidget);
      for (final q in Quadrant.values) {
        expect(find.text('${q.number}'), findsOneWidget);
        expect(find.text(q.adjectives), findsOneWidget);
      }

      final titleBottom = tester.getBottomLeft(find.byType(TextField)).dy;
      final quadrantTop = tester.getTopLeft(find.text('領域')).dy;
      final timeTop = tester.getTopLeft(find.text('6月23日 (火) 20:15')).dy;
      expect(quadrantTop, greaterThan(titleBottom));
      expect(timeTop, greaterThan(quadrantTop));
    });

    testWidgets('プリセットチップが設定から表示される', (tester) async {
      await _pumpHarness(tester, onResult: (_) {});

      expect(find.text('15分'), findsOneWidget);
      expect(find.text('30分'), findsOneWidget);
      expect(find.text('1時間'), findsOneWidget);
      expect(find.text('3時間'), findsOneWidget);
      expect(find.text('自由入力'), findsOneWidget);
    });

    testWidgets('チップを選んで保存すると durationMinutes に反映される', (tester) async {
      QuickCreateResult? captured;
      await _pumpHarness(tester, onResult: (result) => captured = result);

      await tester.enterText(find.byType(TextField), '打ち合わせ');
      await tester.tap(find.text('45分'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(captured?.title, '打ち合わせ');
      expect(captured?.durationMinutes, 45);
      expect(captured?.quadrant, Quadrant.urgentImportant);
    });

    testWidgets('チップ未選択の間は保存できない（デフォルト選択なし）', (tester) async {
      QuickCreateResult? captured;
      await _pumpHarness(tester, onResult: (result) => captured = result);

      await tester.enterText(find.byType(TextField), '打ち合わせ');
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '保存'),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.text('保存'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(captured, isNull);
      expect(find.text('予定を追加'), findsOneWidget);
    });

    testWidgets('選択した領域が保存結果に含まれる', (tester) async {
      QuickCreateResult? captured;
      await _pumpHarness(tester, onResult: (result) => captured = result);

      await tester.enterText(find.byType(TextField), '資料整理');
      await tester.tap(find.text('×緊急・×重要'));
      await tester.pump();
      await tester.tap(find.text('30分'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(captured?.quadrant, Quadrant.notUrgentNotImportant);
      expect(captured?.durationMinutes, 30);
    });

    testWidgets('空タイトルでは保存しても閉じない', (tester) async {
      QuickCreateResult? captured;
      await _pumpHarness(tester, onResult: (result) => captured = result);

      await tester.tap(find.text('15分'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(captured, isNull);
      expect(find.text('予定を追加'), findsOneWidget);
    });

    testWidgets('自由入力で任意の分数を選べる', (tester) async {
      QuickCreateResult? captured;
      await _pumpHarness(tester, onResult: (result) => captured = result);

      await tester.enterText(find.byType(TextField), '執筆');
      await tester.tap(find.text('自由入力'));
      await tester.pumpAndSettle();

      // ダイアログの分数入力（最後に出現した TextField）へ入力して決定。
      await tester.enterText(find.byType(TextField).last, '25');
      await tester.tap(find.text('決定'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(captured?.durationMinutes, 25);
    });

    testWidgets('狭幅かつキーボード表示相当でもオーバーフローしない', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);

      await _pumpHarness(tester, onResult: (_) {});
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('領域'), findsOneWidget);
    });
  });
}
