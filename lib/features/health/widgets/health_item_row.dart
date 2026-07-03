import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/health/model/health_category.dart';
import 'package:task_manager/features/health/model/health_log.dart';
import 'package:task_manager/features/health/model/health_scoring.dart';
import 'package:task_manager/features/health/viewmodel/health_detail_viewmodel.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/utils/app_messenger.dart';

/// 健康詳細画面の1カテゴリ分の行。3列レイアウト:
///   左: 目標（「目標」横に保存・桁幅に合わせた数値入力） / 中央: 現状値（スライダー） /
///   右: 10段階・点数・カテゴリ獲得金額
class HealthItemRow extends ConsumerStatefulWidget {
  const HealthItemRow({
    super.key,
    required this.category,
    required this.log,
    required this.settings,
    required this.enabled,
  });

  final HealthCategory category;
  final HealthLog log;
  final UserSettings settings;
  final bool enabled;

  @override
  ConsumerState<HealthItemRow> createState() => _HealthItemRowState();
}

class _HealthItemRowState extends ConsumerState<HealthItemRow> {
  static const double _goalColumnWidth = 120;
  static const double _sleepGoalColumnWidth = 132;
  static const double _statsColumnWidth = 52;

  late final TextEditingController _primaryCtrl;
  late final TextEditingController _sleepHoursCtrl;
  late final TextEditingController _sleepMinsCtrl;

  @override
  void initState() {
    super.initState();
    _primaryCtrl = TextEditingController();
    _sleepHoursCtrl = TextEditingController();
    _sleepMinsCtrl = TextEditingController();
    _syncFromSettings(widget.settings);
  }

  @override
  void didUpdateWidget(HealthItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_goalFieldsEqual(oldWidget.settings, widget.settings)) {
      _syncFromSettings(widget.settings);
    }
  }

  @override
  void dispose() {
    _primaryCtrl.dispose();
    _sleepHoursCtrl.dispose();
    _sleepMinsCtrl.dispose();
    super.dispose();
  }

  bool _goalFieldsEqual(UserSettings a, UserSettings b) {
    return switch (widget.category) {
      HealthCategory.meal => a.mealGoalGrams == b.mealGoalGrams,
      HealthCategory.exercise => a.exerciseGoalMinutes == b.exerciseGoalMinutes,
      HealthCategory.sleep =>
        a.sleepGoalHours == b.sleepGoalHours &&
            a.sleepGoalMinutesExtra == b.sleepGoalMinutesExtra,
      HealthCategory.meditation =>
        a.meditationGoalMinutes == b.meditationGoalMinutes,
    };
  }

  void _syncFromSettings(UserSettings s) {
    switch (widget.category) {
      case HealthCategory.meal:
        _primaryCtrl.text = s.mealGoalGrams == 0 ? '' : '${s.mealGoalGrams}';
        break;
      case HealthCategory.exercise:
        _primaryCtrl.text = s.exerciseGoalMinutes == 0
            ? ''
            : '${s.exerciseGoalMinutes}';
        break;
      case HealthCategory.sleep:
        _sleepHoursCtrl.text = s.sleepGoalHours == 0
            ? ''
            : '${s.sleepGoalHours}';
        _sleepMinsCtrl.text = s.sleepGoalMinutesExtra == 0
            ? ''
            : '${s.sleepGoalMinutesExtra}';
        break;
      case HealthCategory.meditation:
        _primaryCtrl.text = s.meditationGoalMinutes == 0
            ? ''
            : '${s.meditationGoalMinutes}';
        break;
    }
  }

  InputDecoration _numberFieldDecoration() {
    return InputDecoration(
      isDense: true,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    );
  }

  /// 半角数字 [digitCount] 桁分の幅（枠・パディング込みの目安）
  double _halfWidthDigitFieldWidth(
    BuildContext context,
    TextStyle? fieldStyle,
    int digitCount,
  ) {
    final style = fieldStyle ?? Theme.of(context).textTheme.bodySmall!;
    final tp = TextPainter(
      text: TextSpan(text: '0' * digitCount, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return tp.width + 6 * 2 + 10;
  }

  double _goalColumnWidthForCategory() {
    return switch (widget.category) {
      HealthCategory.sleep => _sleepGoalColumnWidth,
      HealthCategory.meal ||
      HealthCategory.exercise ||
      HealthCategory.meditation =>
        _goalColumnWidth,
    };
  }

  Widget _goalSaveControl(TextTheme text, ColorScheme scheme) {
    final saving = ref.watch(userSettingsProvider).isSaving;
    final labelStyle = text.labelSmall;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.65)),
      ),
      onPressed: saving ? null : _saveGoal,
      child: Text(
        '保存',
        style: labelStyle?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _goalLabelRow(TextTheme text, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('目標', style: text.labelSmall),
        if (widget.enabled) ...[
          const SizedBox(width: 8),
          _goalSaveControl(text, scheme),
        ],
      ],
    );
  }

  Future<void> _saveGoal() async {
    final base = ref.read(userSettingsProvider).settings;
    final UserSettings updated;
    switch (widget.category) {
      case HealthCategory.meal:
        updated = base.copyWith(
          mealGoalGrams: int.tryParse(_primaryCtrl.text) ?? 0,
        );
        break;
      case HealthCategory.exercise:
        updated = base.copyWith(
          exerciseGoalMinutes: int.tryParse(_primaryCtrl.text) ?? 0,
        );
        break;
      case HealthCategory.sleep:
        final h = int.tryParse(_sleepHoursCtrl.text);
        final m = int.tryParse(_sleepMinsCtrl.text);
        if (_sleepHoursCtrl.text.isNotEmpty && (h == null || h < 0)) {
          _showInvalid('睡眠（時間）は0以上の数で入力してください');
          return;
        }
        if (_sleepMinsCtrl.text.isNotEmpty && (m == null || m < 0 || m > 59)) {
          _showInvalid('睡眠（分）は0〜59で入力してください');
          return;
        }
        updated = base.copyWith(
          sleepGoalHours: h ?? 0,
          sleepGoalMinutesExtra: m ?? 0,
        );
        break;
      case HealthCategory.meditation:
        updated = base.copyWith(
          meditationGoalMinutes: int.tryParse(_primaryCtrl.text) ?? 0,
        );
        break;
    }

    final validationError = widget.category.validateGoal(updated);
    if (validationError != null) {
      _showInvalid(validationError);
      return;
    }

    final vm = ref.read(userSettingsProvider.notifier);
    vm.update(updated);
    final success = await vm.save();
    if (!mounted) return;
    if (success) {
      showAppSnackBar(
        context,
        const SnackBar(content: Text('目標を保存しました')),
        blocking: false,
      );
    } else {
      final err = ref.read(userSettingsProvider).errorMessage;
      showAppSnackBar(
        context,
        SnackBar(
          content: Text(err ?? '保存に失敗しました'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showInvalid(String message) {
    showAppSnackBar(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(userSettingsProvider).settings;

    final current = widget.category.currentValue(widget.log);
    final level = widget.category.level(widget.log, settings);
    final score = widget.category.score(widget.log);
    final maxPoints = widget.category.maxPoints;
    final earnings = HealthScoring.earningsForPoints(
      score,
      settings.hourlyRate,
    );

    final sliderLevel = widget.category.levelForValue(current, settings);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.category.icon, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  widget.category.label,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _goalColumnWidthForCategory(),
                  child: _buildGoalInputsColumn(text, scheme),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.category.formatValue(current),
                        textAlign: TextAlign.center,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                      SizedBox(
                        height: 28,
                        width: double.infinity,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                          ),
                          child: Slider(
                            value: sliderLevel.clamp(0, 10).toDouble(),
                            min: 0,
                            max: 10,
                            divisions: 10,
                            onChanged: widget.enabled
                                ? (v) {
                                    final value = widget.category.valueForLevel(
                                      v.round(),
                                      settings,
                                    );
                                    ref
                                        .read(
                                          healthDetailViewModelProvider
                                              .notifier,
                                        )
                                        .previewValue(widget.category, value);
                                  }
                                : null,
                            onChangeEnd: widget.enabled
                                ? (v) {
                                    final value = widget.category.valueForLevel(
                                      v.round(),
                                      settings,
                                    );
                                    ref
                                        .read(
                                          healthDetailViewModelProvider
                                              .notifier,
                                        )
                                        .commitValue(widget.category, value);
                                  }
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: _statsColumnWidth,
                  child: Transform.translate(
                    offset: const Offset(0, -2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        RichText(
                          textAlign: TextAlign.right,
                          text: TextSpan(
                            style: text.bodyMedium?.copyWith(height: 1),
                            children: [
                              TextSpan(
                                text: '$level',
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary,
                                  height: 1,
                                ),
                              ),
                              const TextSpan(text: '/10'),
                            ],
                          ),
                        ),
                        Text(
                          '$score/$maxPoints点',
                          style: text.labelSmall?.copyWith(height: 1),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '+¥${_fmtYen(earnings)}',
                          style: text.titleSmall?.copyWith(
                            color: scheme.tertiary,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalInputsColumn(TextTheme text, ColorScheme scheme) {
    final bodySmall = text.bodySmall;
    switch (widget.category) {
      case HealthCategory.sleep:
        final w2 = _halfWidthDigitFieldWidth(context, bodySmall, 2);
        Widget sleepValueField({
          required TextEditingController controller,
          required String unit,
          required int maxLen,
        }) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: w2,
                child: TextField(
                  controller: controller,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(maxLen),
                  ],
                  decoration: _numberFieldDecoration(),
                  style: bodySmall,
                ),
              ),
              const SizedBox(width: 4),
              Text(unit, style: bodySmall),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _goalLabelRow(text, scheme),
            const SizedBox(height: 4),
            Row(
              children: [
                sleepValueField(
                  controller: _sleepHoursCtrl,
                  unit: '時間',
                  maxLen: 2,
                ),
                const SizedBox(width: 6),
                sleepValueField(
                  controller: _sleepMinsCtrl,
                  unit: '分',
                  maxLen: 2,
                ),
              ],
            ),
          ],
        );
      case HealthCategory.meal:
      case HealthCategory.exercise:
      case HealthCategory.meditation:
        final unitLabel = switch (widget.category) {
          HealthCategory.meal => 'g',
          HealthCategory.exercise || HealthCategory.meditation => '分',
          _ => '',
        };
        final w4 = _halfWidthDigitFieldWidth(context, bodySmall, 4);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _goalLabelRow(text, scheme),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: w4,
                  child: TextField(
                    controller: _primaryCtrl,
                    enabled: widget.enabled,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: _numberFieldDecoration(),
                    style: bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(unitLabel, style: bodySmall),
                ),
              ],
            ),
          ],
        );
    }
  }

  String _fmtYen(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
}
