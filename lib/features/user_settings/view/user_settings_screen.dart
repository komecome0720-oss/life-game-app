import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/features/user_settings/widgets/hourly_rate_display.dart';
import 'package:task_manager/features/user_settings/widgets/profile_image_picker.dart';
import 'package:task_manager/features/user_settings/widgets/settings_number_field.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/message_guard.dart';

class UserSettingsScreen extends ConsumerStatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  ConsumerState<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends ConsumerState<UserSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _levelCtrl;
  late final TextEditingController _budgetCtrl;
  late final TextEditingController _daysCtrl;
  late final TextEditingController _minutesCtrl;

  File? _pendingAvatarFile;
  int? _pendingPresetIndex;
  bool _initialized = false;

  double get _localHourlyRate {
    final budget = int.tryParse(_budgetCtrl.text) ?? 0;
    final days = int.tryParse(_daysCtrl.text) ?? 0;
    final mins = int.tryParse(_minutesCtrl.text) ?? 0;
    final totalMins = days * mins;
    if (totalMins <= 0) return 0;
    return budget / (totalMins / 60);
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _levelCtrl = TextEditingController();
    _budgetCtrl = TextEditingController();
    _daysCtrl = TextEditingController();
    _minutesCtrl = TextEditingController();

    for (final ctrl in [_budgetCtrl, _daysCtrl, _minutesCtrl]) {
      ctrl.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final ctrl in [_nameCtrl, _levelCtrl, _budgetCtrl, _daysCtrl, _minutesCtrl]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _initControllers(UserSettings s) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = s.displayName;
    _levelCtrl.text = s.level <= 1 ? '' : '${s.level}';
    _budgetCtrl.text = s.monthlyBudget == 0 ? '' : '${s.monthlyBudget}';
    _daysCtrl.text = s.monthlyQuestDays == 0 ? '' : '${s.monthlyQuestDays}';
    _minutesCtrl.text = s.dailyQuestMinutes == 0 ? '' : '${s.dailyQuestMinutes}';
  }

  UserSettings _currentSettings() {
    final base = ref.read(userSettingsProvider).settings;
    return base.copyWith(
      displayName: _nameCtrl.text.trim(),
      level: int.tryParse(_levelCtrl.text) ?? 1,
      monthlyBudget: int.tryParse(_budgetCtrl.text) ?? 0,
      monthlyQuestDays: int.tryParse(_daysCtrl.text) ?? 0,
      dailyQuestMinutes: int.tryParse(_minutesCtrl.text) ?? 0,
    );
  }

  void _showBalanceAdjustDialog() {
    final ctrl = TextEditingController();
    bool isAdding = true;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('所持金を増減'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToggleButtons(
                isSelected: [isAdding, !isAdding],
                onPressed: (i) => setDialogState(() => isAdding = i == 0),
                borderRadius: BorderRadius.circular(8),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('受け取る (+)')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('使う (−)')),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '金額',
                  prefixText: '¥',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            TextButton(
              onPressed: () {
                final amount = int.tryParse(ctrl.text) ?? 0;
                if (amount > 0) {
                  final delta = isAdding ? amount : -amount;
                  ref.read(userSettingsProvider.notifier).adjustBalance(delta);
                }
                Navigator.pop(ctx);
              },
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final vm = ref.read(userSettingsProvider.notifier);

    String? avatarUrl;
    if (_pendingAvatarFile != null) {
      avatarUrl = await vm.uploadAvatar(_pendingAvatarFile!);
    }

    final updated = _currentSettings().copyWith(
      avatarUrl: avatarUrl ?? ref.read(userSettingsProvider).settings.avatarUrl,
    );
    vm.update(updated);

    final success = await vm.save();
    if (!mounted) return;

    final errorMsg = ref.read(userSettingsProvider).errorMessage;
    showAppSnackBar(
      context,
      SnackBar(
        content: Text(success ? '保存しました' : (errorMsg ?? '保存に失敗しました')),
        backgroundColor: success ? null : Colors.red,
      ),
    );
    if (success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userSettingsProvider);

    // ロード完了をストリームで検知
    ref.listen<UserSettingsState>(userSettingsProvider, (prev, next) {
      if (!next.isLoading && (prev == null || prev.isLoading)) {
        _initControllers(next.settings);
      }
    });

    // 既にロード済みの状態で画面を開いた場合（2回目以降）
    if (!state.isLoading && !_initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _initControllers(state.settings);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール設定'),
        actions: [
          state.isSaving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
        ],
      ),
      body: MessageGuard(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                  _SectionHeader('基本情報'),
                  const SizedBox(height: 12),
                  Center(
                    child: ProfileImagePicker(
                      avatarUrl: _pendingPresetIndex != null ? '' : state.settings.avatarUrl,
                      onFileSelected: (file) => setState(() {
                        _pendingAvatarFile = file;
                        _pendingPresetIndex = null;
                      }),
                      onPresetSelected: (i) => setState(() {
                        _pendingPresetIndex = i;
                        _pendingAvatarFile = null;
                      }),
                    ),
                  ),
                  if (_pendingPresetIndex != null) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: presetAvatarColor(_pendingPresetIndex!).withOpacity(0.2),
                        child: Icon(presetAvatarIcon(_pendingPresetIndex!),
                            color: presetAvatarColor(_pendingPresetIndex!), size: 24),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _Field(
                    controller: _nameCtrl,
                    label: '名前',
                    validator: (v) => (v == null || v.trim().isEmpty) ? '名前を入力してください' : null,
                  ),
                  const SizedBox(height: 12),
                  SettingsNumberField(
                    controller: _levelCtrl,
                    label: 'レベル',
                    suffix: '',
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (v != null && v.isNotEmpty && (n == null || n < 1)) return '1以上';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _BalanceRow(
                    balanceYen: state.settings.totalEarned,
                    onAdjust: _showBalanceAdjustDialog,
                  ),
                  const SizedBox(height: 24),
                  _SectionHeader('報酬設定'),
                  const SizedBox(height: 12),
                  SettingsNumberField(controller: _budgetCtrl, label: '① 月に使えるお金', suffix: '円',
                      validator: (v) => _validatePositive(v, '金額')),
                  const SizedBox(height: 12),
                  SettingsNumberField(controller: _daysCtrl, label: '② 月のクエスト日数', suffix: '日',
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n <= 0) return '日数を入力してください';
                        if (n > 31) return '31日以下で入力してください';
                        return null;
                      }),
                  const SizedBox(height: 12),
                  SettingsNumberField(controller: _minutesCtrl, label: '③ 1日の想定クエスト時間', suffix: '分',
                      validator: (v) => _validatePositive(v, '時間')),
                  const SizedBox(height: 12),
                  HourlyRateDisplay(hourlyRate: _localHourlyRate),
                  const SizedBox(height: 24),
                  _SectionHeader('表示設定'),
                  const SizedBox(height: 12),
                  _DisplaySettings(
                    settings: state.settings,
                    onChanged: (updated) =>
                        ref.read(userSettingsProvider.notifier).update(updated),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
      ),
    );
  }

  String? _validatePositive(String? v, String label) {
    final n = int.tryParse(v ?? '');
    if (n == null || n <= 0) return '$labelを入力してください';
    return null;
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

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.label, this.validator});
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: validator,
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.balanceYen, required this.onAdjust});
  final int balanceYen;
  final VoidCallback onAdjust;

  String _fmt(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: '所持金',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '¥${_fmt(balanceYen)}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '手動で増減',
            onPressed: onAdjust,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

/// 表示設定（テーマ・週の始まり）。選択即時反映、保存ボタンで Firestore に永続化。
class _DisplaySettings extends StatelessWidget {
  const _DisplaySettings({required this.settings, required this.onChanged});

  final UserSettings settings;
  final ValueChanged<UserSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                onChanged(settings.copyWith(themeMode: set.first)),
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
                DropdownMenuItem(value: DateTime.monday, child: Text('月曜日')),
                DropdownMenuItem(value: DateTime.sunday, child: Text('日曜日')),
                DropdownMenuItem(
                    value: DateTime.saturday, child: Text('土曜日')),
              ],
              onChanged: (v) {
                if (v == null) return;
                onChanged(settings.copyWith(weekStartDay: v));
              },
            ),
          ),
        ),
      ],
    );
  }
}
