import 'package:flutter/material.dart';
import 'package:task_manager/features/economy/model/budget_split.dart';
import 'package:task_manager/features/user_settings/widgets/hourly_rate_display.dart';
import 'package:task_manager/features/user_settings/widgets/settings_number_field.dart';

/// オンボーディング②：ステータス入力フォーム（純粋ウィジェット）。
///
/// 名前・月に使えるお金・月のクエスト日数・1日の想定クエスト時間を入力させる。
/// 必須項目のためスキップボタンは持たない。
class StatusFormInitial {
  const StatusFormInitial({
    required this.displayName,
    required this.monthlyBudget,
    required this.monthlyQuestDays,
    required this.dailyQuestMinutes,
  });

  final String displayName;
  final int monthlyBudget;
  final int monthlyQuestDays;
  final int dailyQuestMinutes;
}

class StatusForm extends StatefulWidget {
  const StatusForm({super.key, required this.initial, required this.onSubmit});

  final StatusFormInitial initial;
  final void Function(
    String displayName,
    int monthlyBudget,
    int monthlyQuestDays,
    int dailyQuestMinutes,
  )
  onSubmit;

  @override
  State<StatusForm> createState() => _StatusFormState();
}

class _StatusFormState extends State<StatusForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _budgetCtrl;
  late final TextEditingController _daysCtrl;
  late final TextEditingController _minutesCtrl;

  double get _hourlyRate {
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
    _nameCtrl = TextEditingController(text: widget.initial.displayName);
    _budgetCtrl = TextEditingController(
      text: widget.initial.monthlyBudget == 0
          ? ''
          : '${widget.initial.monthlyBudget}',
    );
    _daysCtrl = TextEditingController(
      text: widget.initial.monthlyQuestDays == 0
          ? ''
          : '${widget.initial.monthlyQuestDays}',
    );
    _minutesCtrl = TextEditingController(
      text: widget.initial.dailyQuestMinutes == 0
          ? ''
          : '${widget.initial.dailyQuestMinutes}',
    );
  }

  @override
  void dispose() {
    for (final ctrl in [_nameCtrl, _budgetCtrl, _daysCtrl, _minutesCtrl]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  String? _validatePositive(String? v, String label) {
    final n = int.tryParse(v ?? '');
    if (n == null || n <= 0) return '$labelを入力してください';
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit(
      _nameCtrl.text.trim(),
      int.tryParse(_budgetCtrl.text) ?? 0,
      int.tryParse(_daysCtrl.text) ?? 0,
      int.tryParse(_minutesCtrl.text) ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          children: [
            Text(
              'あなたのステータスを教えてね',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameCtrl,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: '名前',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '名前を入力してください' : null,
            ),
            const SizedBox(height: 12),
            SettingsNumberField(
              controller: _budgetCtrl,
              label: '① 月に使えるお金',
              suffix: '円',
              validator: (v) => _validatePositive(v, '金額'),
            ),
            const SizedBox(height: 12),
            SettingsNumberField(
              controller: _daysCtrl,
              label: '② 月のクエスト日数',
              suffix: '日',
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n <= 0) return '日数を入力してください';
                if (n > 31) return '31日以下で入力してください';
                return null;
              },
            ),
            const SizedBox(height: 12),
            SettingsNumberField(
              controller: _minutesCtrl,
              label: '③ 1日の想定クエスト時間',
              suffix: '分',
              validator: (v) => _validatePositive(v, '時間'),
            ),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: Listenable.merge([
                _budgetCtrl,
                _daysCtrl,
                _minutesCtrl,
              ]),
              builder: (context, _) => HourlyRateDisplay(
                hourlyRate: _hourlyRate * kTaskBudgetRatio,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _submit,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('次へ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
