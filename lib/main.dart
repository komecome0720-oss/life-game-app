import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/adventure_log/providers/adventure_log_providers.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:task_manager/features/auth/presentation/login_screen.dart';
import 'package:task_manager/features/auth/providers/auth_providers.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/features/todo/view/todo_matrix_screen.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/features/wish_list/view/wish_list_screen.dart';
import 'package:task_manager/firebase_options.dart';
import 'package:task_manager/screens/home_screen.dart';
import 'package:task_manager/theme/app_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('ja_JP');
  runApp(const ProviderScope(child: TaskManagerApp()));
}

class TaskManagerApp extends ConsumerWidget {
  const TaskManagerApp({super.key});

  static const _seedColor = Color(0xFF2E7D6B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeModeStr = ref.watch(
      userSettingsProvider.select((s) => s.settings.themeMode),
    );
    return MaterialApp(
      title: '人生ゲーム化',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
        useMaterial3: true,
        cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: AppRadius.card)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: AppRadius.card)),
      ),
      themeMode: _parseThemeMode(themeModeStr),
      home: const _AuthGate(),
    );
  }
}

ThemeMode _parseThemeMode(String s) {
  switch (s) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return authState.when(
      data: (user) => user != null ? const _MainShell() : const LoginScreen(),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const LoginScreen(),
    );
  }
}

class _MainShell extends ConsumerWidget {
  const _MainShell();

  static const _pages = [HomeScreen(), TodoMatrixScreen(), WishListScreen()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adventureLogBackfillProvider);
    final index = ref.watch(mainTabIndexProvider);
    return Scaffold(
      body: IndexedStack(index: index, children: _pages),
      bottomNavigationBar: NavigationBar(
        height: 50,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(mainTabIndexProvider.notifier).set(i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_box_outlined),
            selectedIcon: Icon(Icons.check_box),
            label: 'ToDo',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: '欲しいもの',
          ),
        ],
      ),
    );
  }
}
