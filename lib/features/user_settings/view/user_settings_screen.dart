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
    _budgetCtrl = TextEditingController();
    _daysCtrl = TextEditingController();
    _minutesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    for (final ctrl in [_nameCtrl, _budgetCtrl, _daysCtrl, _minutesCtrl]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _initControllers(UserSettings s) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = s.displayName;
    _budgetCtrl.text = s.monthlyBudget == 0 ? '' : '${s.monthlyBudget}';
    _daysCtrl.text = s.monthlyQuestDays == 0 ? '' : '${s.monthlyQuestDays}';
    _minutesCtrl.text = s.dailyQuestMinutes == 0 ? '' : '${s.dailyQuestMinutes}';
  }

  UserSettings _currentSettings() {
    final base = ref.read(userSettingsProvider).settings;
    return base.copyWith(
      displayName: _nameCtrl.text.trim(),
      monthlyBudget: int.tryParse(_budgetCtrl.text) ?? 0,
      monthlyQuestDays: int.tryParse(_daysCtrl.text) ?? 0,
      dailyQuestMinutes: int.tryParse(_minutesCtrl.text) ?? 0,
    );
  }

  Future<void> _showBalanceAdjustDialog() async {
    final result = await showDialog<_BalanceAdjustResult>(
      context: context,
      builder: (ctx) => const _BalanceAdjustDialog(),
    );
    if (result == null || result.delta == 0) return;
    await ref.read(userSettingsProvider.notifier).adjustBalance(
          result.delta,
          title: result.delta > 0 ? '手動で受け取り' : '手動で使用',
          note: result.note,
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
        backgroundColor: success ? null : Theme.of(context).colorScheme.error,
      ),
      blocking: !success,
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
                        backgroundColor: presetAvatarColor(_pendingPresetIndex!)
                            .withValues(alpha: 0.2),
                        child: Icon(presetAvatarIcon(_pendingPresetIndex!),
                            color: presetAvatarColor(_pendingPresetIndex!), size: 24),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _Field(
                    controller: _nameCtrl,
                    label: '名前',
                    maxLength: 30,
                    validator: (v) => (v == null || v.trim().isEmpty) ? '名前を入力してください' : null,
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
                  // 時間単価プレビューは3フィールドの入力ごとに再計算が必要なため、
                  // 画面全体ではなくここだけを部分再ビルドする。
                  ListenableBuilder(
                    listenable: Listenable.merge(
                      [_budgetCtrl, _daysCtrl, _minutesCtrl],
                    ),
                    builder: (context, _) =>
                        HourlyRateDisplay(hourlyRate: _localHourlyRate),
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
  const _Field({required this.controller, required this.label, this.validator, this.maxLength});
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLength: maxLength,
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

/// 「所持金を増減」ダイアログの結果（増減額＋メモ）。
class _BalanceAdjustResult {
  const _BalanceAdjustResult({required this.delta, required this.note});

  final int delta;
  final String note;
}

/// 所持金を手動で増減するダイアログ。
///
/// TextEditingController を State で保持し `dispose()` で破棄する（フレームワークが
/// 退場アニメーション完了後に破棄するため、コントローラーの use-after-dispose を防ぐ）。
class _BalanceAdjustDialog extends StatefulWidget {
  const _BalanceAdjustDialog();

  @override
  State<_BalanceAdjustDialog> createState() => _BalanceAdjustDialogState();
}

class _BalanceAdjustDialogState extends State<_BalanceAdjustDialog> {
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  bool _isAdding = true;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = int.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(
      context,
      _BalanceAdjustResult(
        delta: _isAdding ? amount : -amount,
        note: _memoCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('所持金を増減'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ToggleButtons(
            isSelected: [_isAdding, !_isAdding],
            onPressed: (i) => setState(() => _isAdding = i == 0),
            borderRadius: BorderRadius.circular(8),
            children: const [
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('受け取る (+)')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('使う (−)')),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '金額',
              prefixText: '¥',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _memoCtrl,
            textInputAction: TextInputAction.done,
            maxLines: 1,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: 'メモ（任意）',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        TextButton(onPressed: _submit, child: const Text('確定')),
      ],
    );
  }
}
