import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/message_guard.dart';

/// 設定画面（表示設定＝テーマ・週の始まり）。
/// 変更は即時にローカル反映（テーマは main.dart の watch でライブ反映）し、
/// 該当フィールドだけを Firestore へ自動保存する（保存ボタン無し）。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _onThemeChanged(UserSettings current, String themeMode) async {
    final vm = ref.read(userSettingsProvider.notifier);
    vm.update(current.copyWith(themeMode: themeMode));
    final ok = await vm.saveDisplaySettings(themeMode: themeMode);
    if (!ok && mounted) {
      showAppSnackBar(
        context,
        const SnackBar(content: Text('保存に失敗しました')),
      );
    }
  }

  Future<void> _onWeekStartChanged(UserSettings current, int weekStartDay) async {
    final vm = ref.read(userSettingsProvider.notifier);
    vm.update(current.copyWith(weekStartDay: weekStartDay));
    final ok = await vm.saveDisplaySettings(weekStartDay: weekStartDay);
    if (!ok && mounted) {
      showAppSnackBar(
        context,
        const SnackBar(content: Text('保存に失敗しました')),
      );
    }
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
                  _SectionHeader('表示設定'),
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
