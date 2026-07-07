import 'package:flutter/material.dart';
import 'package:task_manager/features/user_settings/widgets/settings_number_field.dart';

/// オンボーディング③：健康目標入力フォーム（純粋ウィジェット）。
///
/// 野菜・果物・運動・睡眠（時間＋分）・瞑想の初期値をプリセットしつつ、
/// 既に0以外の値が保存されているユーザーはその値を初期表示する。
class HealthGoalFormInitial {
  const HealthGoalFormInitial({
    required this.mealGoalGrams,
    required this.exerciseGoalMinutes,
    required this.sleepGoalHours,
    required this.sleepGoalMinutesExtra,
    required this.meditationGoalMinutes,
  });

  final int mealGoalGrams;
  final int exerciseGoalMinutes;
  final int sleepGoalHours;
  final int sleepGoalMinutesExtra;
  final int meditationGoalMinutes;

  static const presetMealGoalGrams = 350;
  static const presetExerciseGoalMinutes = 20;
  static const presetSleepGoalHours = 7;
  static const presetSleepGoalMinutesExtra = 0;
  static const presetMeditationGoalMinutes = 10;
}

class HealthGoalForm extends StatefulWidget {
  const HealthGoalForm({
    super.key,
    required this.initial,
    required this.onSubmit,
    required this.onSkip,
  });

  final HealthGoalFormInitial initial;
  final void Function(
    int mealGoalGrams,
    int exerciseGoalMinutes,
    int sleepGoalHours,
    int sleepGoalMinutesExtra,
    int meditationGoalMinutes,
  )
  onSubmit;
  final VoidCallback onSkip;

  @override
  State<HealthGoalForm> createState() => _HealthGoalFormState();
}

class _HealthGoalFormState extends State<HealthGoalForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _mealCtrl;
  late final TextEditingController _exerciseCtrl;
  late final TextEditingController _sleepHourCtrl;
  late final TextEditingController _sleepMinuteCtrl;
  late final TextEditingController _meditationCtrl;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _mealCtrl = TextEditingController(
      text:
          '${i.mealGoalGrams == 0 ? HealthGoalFormInitial.presetMealGoalGrams : i.mealGoalGrams}',
    );
    _exerciseCtrl = TextEditingController(
      text:
          '${i.exerciseGoalMinutes == 0 ? HealthGoalFormInitial.presetExerciseGoalMinutes : i.exerciseGoalMinutes}',
    );
    _sleepHourCtrl = TextEditingController(
      text:
          '${i.sleepGoalHours == 0 ? HealthGoalFormInitial.presetSleepGoalHours : i.sleepGoalHours}',
    );
    // 睡眠の分は「0分」自体が有効なプリセット値のため、時間が未設定（0）の場合のみプリセットを適用する。
    _sleepMinuteCtrl = TextEditingController(
      text: i.sleepGoalHours == 0
          ? '${HealthGoalFormInitial.presetSleepGoalMinutesExtra}'
          : '${i.sleepGoalMinutesExtra}',
    );
    _meditationCtrl = TextEditingController(
      text:
          '${i.meditationGoalMinutes == 0 ? HealthGoalFormInitial.presetMeditationGoalMinutes : i.meditationGoalMinutes}',
    );
  }

  @override
  void dispose() {
    for (final ctrl in [
      _mealCtrl,
      _exerciseCtrl,
      _sleepHourCtrl,
      _sleepMinuteCtrl,
      _meditationCtrl,
    ]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  String? _validateNonNegative(String? v) {
    final n = int.tryParse(v ?? '');
    if (n == null || n < 0) return '0以上の数値を入力してください';
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit(
      int.tryParse(_mealCtrl.text) ?? 0,
      int.tryParse(_exerciseCtrl.text) ?? 0,
      int.tryParse(_sleepHourCtrl.text) ?? 0,
      int.tryParse(_sleepMinuteCtrl.text) ?? 0,
      int.tryParse(_meditationCtrl.text) ?? 0,
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
              '健康目標を決めよう',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'おすすめの数値を入れておいたよ。あとで設定画面からいつでも変更できるよ',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            SettingsNumberField(
              controller: _mealCtrl,
              label: '野菜・果物',
              suffix: 'g',
              validator: _validateNonNegative,
            ),
            const SizedBox(height: 12),
            SettingsNumberField(
              controller: _exerciseCtrl,
              label: '運動',
              suffix: '分',
              validator: _validateNonNegative,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SettingsNumberField(
                    controller: _sleepHourCtrl,
                    label: '睡眠',
                    suffix: '時間',
                    validator: _validateNonNegative,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SettingsNumberField(
                    controller: _sleepMinuteCtrl,
                    label: '（追加）',
                    suffix: '分',
                    validator: _validateNonNegative,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SettingsNumberField(
              controller: _meditationCtrl,
              label: '瞑想',
              suffix: '分',
              validator: _validateNonNegative,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _submit,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('この目標で始める'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: widget.onSkip, child: const Text('あとで設定')),
          ],
        ),
      ),
    );
  }
}
