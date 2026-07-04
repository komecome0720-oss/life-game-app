import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/message_guard.dart';

/// 設定画面（一般＝テーマ・週の始まり／ToDo／カレンダー）。
/// 変更は即時にローカル反映（テーマは main.dart の watch でライブ反映）し、
/// 該当フィールドだけを Firestore へ自動保存する（保存ボタン無し）。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _persist({
    String? themeMode,
    int? weekStartDay,
    int? defaultTodoEstimatedMinutes,
    int? defaultCalendarDurationMinutes,
  }) async {
    final vm = ref.read(userSettingsProvider.notifier);
    final ok = await vm.savePreferences(
      themeMode: themeMode,
      weekStartDay: weekStartDay,
      defaultTodoEstimatedMinutes: defaultTodoEstimatedMinutes,
      defaultCalendarDurationMinutes: defaultCalendarDurationMinutes,
    );
    if (!ok && mounted) {
      showAppSnackBar(
        context,
        const SnackBar(content: Text('保存に失敗しました')),
      );
    }
  }

  Future<void> _onThemeChanged(UserSettings current, String themeMode) async {
    ref.read(userSettingsProvider.notifier).update(
          current.copyWith(themeMode: themeMode),
        );
    await _persist(themeMode: themeMode);
  }

  Future<void> _onWeekStartChanged(
      UserSettings current, int weekStartDay) async {
    ref.read(userSettingsProvider.notifier).update(
          current.copyWith(weekStartDay: weekStartDay),
        );
    await _persist(weekStartDay: weekStartDay);
  }

  Future<void> _onTodoMinutesChanged(UserSettings current, int minutes) async {
    ref.read(userSettingsProvider.notifier).update(
          current.copyWith(defaultTodoEstimatedMinutes: minutes),
        );
    await _persist(defaultTodoEstimatedMinutes: minutes);
  }

  Future<void> _onCalendarMinutesChanged(
      UserSettings current, int minutes) async {
    ref.read(userSettingsProvider.notifier).update(
          current.copyWith(defaultCalendarDurationMinutes: minutes),
        );
    await _persist(defaultCalendarDurationMinutes: minutes);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userSettingsProvider);
    final settings = state.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: MessageGuard(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionHeader('一般'),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'テーマ',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'system', label: Text('自動')),
                        ButtonSegment(value: 'light', label: Text('ライト')),
                        ButtonSegment(value: 'dark', label: Text('ダーク')),
                      ],
                      selected: {settings.themeMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (set) =>
                          _onThemeChanged(settings, set.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '週の始まり',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: settings.weekStartDay,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                              value: DateTime.monday, child: Text('月曜日')),
                          DropdownMenuItem(
                              value: DateTime.sunday, child: Text('日曜日')),
                          DropdownMenuItem(
                              value: DateTime.saturday, child: Text('土曜日')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          _onWeekStartChanged(settings, v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SectionHeader('ToDo'),
                  const SizedBox(height: 12),
                  _MinutesStepperTile(
                    label: '見込時間のデフォルト',
                    minutes: settings.defaultTodoEstimatedMinutes,
                    onChanged: (m) => _onTodoMinutesChanged(settings, m),
                  ),
                  const SizedBox(height: 24),
                  _SectionHeader('カレンダー'),
                  const SizedBox(height: 12),
                  _MinutesStepperTile(
                    label: '新規予定の所要時間デフォルト',
                    minutes: settings.defaultCalendarDurationMinutes,
                    onChanged: (m) => _onCalendarMinutesChanged(settings, m),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ));
  }
}

/// 5分刻み・5〜600分クランプのステッパー付き設定行。
class _MinutesStepperTile extends StatelessWidget {
  const _MinutesStepperTile({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  String _format(int m) {
    if (m < 60) return '$m分';
    if (m % 60 == 0) return '${m ~/ 60}時間';
    return '${m ~/ 60}時間${m % 60}分';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InputDecorator(
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.bodyMedium)),
          IconButton.outlined(
            onPressed: () => onChanged((minutes - 5).clamp(5, 600)),
            icon: const Icon(Icons.remove),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              _format(minutes),
              textAlign: TextAlign.center,
              style: text.titleSmall,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            onPressed: () => onChanged((minutes + 5).clamp(5, 600)),
            icon: const Icon(Icons.add),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
