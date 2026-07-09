import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/pomodoro/model/pomodoro_settings.dart';
import 'package:task_manager/features/pomodoro/providers/pomodoro_providers.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/message_guard.dart';

/// ポモドーロ設定画面。
///
/// N/M/K/L の数値（1〜999分・1〜999セット）、BGM3種・切り替え音3種を編集し、
/// 保存ボタンで Firestore（`users/{uid}/settings/pomodoro`）へ書き込む。
/// 設定を一度も開かなくても既定値でポモドーロを開始できる（確定仕様10）。
class PomodoroSettingsScreen extends ConsumerStatefulWidget {
  const PomodoroSettingsScreen({super.key});

  @override
  ConsumerState<PomodoroSettingsScreen> createState() =>
      _PomodoroSettingsScreenState();
}

class _PomodoroSettingsScreenState
    extends ConsumerState<PomodoroSettingsScreen> {
  late TextEditingController _workCtrl;
  late TextEditingController _shortBreakCtrl;
  late TextEditingController _setCountCtrl;
  late TextEditingController _longBreakCtrl;
  PomodoroBgm _bgmWork = PomodoroSettings.defaultBgmWork;
  PomodoroBgm _bgmShortBreak = PomodoroSettings.defaultBgmShortBreak;
  PomodoroBgm _bgmLongBreak = PomodoroSettings.defaultBgmLongBreak;
  PomodoroChime _soundWorkStart = PomodoroSettings.defaultSoundWorkStart;
  PomodoroChime _soundShortBreakStart =
      PomodoroSettings.defaultSoundShortBreakStart;
  PomodoroChime _soundLongBreakStart =
      PomodoroSettings.defaultSoundLongBreakStart;

  bool _initialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _workCtrl = TextEditingController();
    _shortBreakCtrl = TextEditingController();
    _setCountCtrl = TextEditingController();
    _longBreakCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _workCtrl.dispose();
    _shortBreakCtrl.dispose();
    _setCountCtrl.dispose();
    _longBreakCtrl.dispose();
    super.dispose();
  }

  void _applySettings(PomodoroSettings settings) {
    _workCtrl.text = settings.workMinutes.toString();
    _shortBreakCtrl.text = settings.shortBreakMinutes.toString();
    _setCountCtrl.text = settings.setCount.toString();
    _longBreakCtrl.text = settings.longBreakMinutes.toString();
    _bgmWork = settings.bgmWork;
    _bgmShortBreak = settings.bgmShortBreak;
    _bgmLongBreak = settings.bgmLongBreak;
    _soundWorkStart = settings.soundWorkStart;
    _soundShortBreakStart = settings.soundShortBreakStart;
    _soundLongBreakStart = settings.soundLongBreakStart;
  }

  int _parseMinutes(TextEditingController ctrl, int fallback) {
    final v = int.tryParse(ctrl.text.trim());
    if (v == null || v <= 0) return fallback;
    return v;
  }

  Future<void> _onTapPreview(String assetPath) async {
    await ref.read(pomodoroAudioProvider).preview(assetPath);
  }

  Future<void> _onTapSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final settings = PomodoroSettings(
      workMinutes:
          _parseMinutes(_workCtrl, PomodoroSettings.defaultWorkMinutes),
      shortBreakMinutes: _parseMinutes(
          _shortBreakCtrl, PomodoroSettings.defaultShortBreakMinutes),
      setCount:
          _parseMinutes(_setCountCtrl, PomodoroSettings.defaultSetCount),
      longBreakMinutes: _parseMinutes(
          _longBreakCtrl, PomodoroSettings.defaultLongBreakMinutes),
      bgmWork: _bgmWork,
      bgmShortBreak: _bgmShortBreak,
      bgmLongBreak: _bgmLongBreak,
      soundWorkStart: _soundWorkStart,
      soundShortBreakStart: _soundShortBreakStart,
      soundLongBreakStart: _soundLongBreakStart,
    );
    try {
      await ref.read(pomodoroSettingsRepositoryProvider).save(settings);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showAppSnackBar(context, const SnackBar(content: Text('保存に失敗しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncSettings = ref.watch(pomodoroSettingsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('ポモドーロ設定')),
      body: MessageGuard(
        child: asyncSettings.when(
          data: (settings) {
            if (!_initialized) {
              _applySettings(settings);
              _initialized = true;
            }
            return _buildForm(context);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) {
            if (!_initialized) {
              _applySettings(PomodoroSettings.defaults);
              _initialized = true;
            }
            return _buildForm(context);
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader('時間'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MinutesField(
                label: 'クエスト時間',
                suffixText: '分',
                controller: _workCtrl,
                min: 1,
                max: 120,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MinutesField(
                label: '休憩時間',
                suffixText: '分',
                controller: _shortBreakCtrl,
                min: 1,
                max: 60,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MinutesField(
                label: 'セット数',
                controller: _setCountCtrl,
                min: 1,
                max: 20,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MinutesField(
                label: '長休憩時間',
                suffixText: '分',
                controller: _longBreakCtrl,
                min: 1,
                max: 60,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SectionHeader('BGM'),
        const SizedBox(height: 12),
        _BgmDropdown(
          label: 'クエスト中BGM',
          value: _bgmWork,
          onChanged: (v) => setState(() => _bgmWork = v),
          onPreview: _onTapPreview,
        ),
        const SizedBox(height: 12),
        _BgmDropdown(
          label: '休憩中BGM',
          value: _bgmShortBreak,
          onChanged: (v) => setState(() => _bgmShortBreak = v),
          onPreview: _onTapPreview,
        ),
        const SizedBox(height: 12),
        _BgmDropdown(
          label: '長休憩中BGM',
          value: _bgmLongBreak,
          onChanged: (v) => setState(() => _bgmLongBreak = v),
          onPreview: _onTapPreview,
        ),
        const SizedBox(height: 24),
        _SectionHeader('切り替え音'),
        const SizedBox(height: 12),
        _ChimeDropdown(
          label: 'クエスト開始音',
          value: _soundWorkStart,
          onChanged: (v) => setState(() => _soundWorkStart = v),
          onPreview: _onTapPreview,
        ),
        const SizedBox(height: 12),
        _ChimeDropdown(
          label: '休憩開始音',
          value: _soundShortBreakStart,
          onChanged: (v) => setState(() => _soundShortBreakStart = v),
          onPreview: _onTapPreview,
        ),
        const SizedBox(height: 12),
        _ChimeDropdown(
          label: '長休憩開始音',
          value: _soundLongBreakStart,
          onChanged: (v) => setState(() => _soundLongBreakStart = v),
          onPreview: _onTapPreview,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isSaving ? null : _onTapSave,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

/// [min]〜[max]の範囲をドラムロール（`CupertinoPicker`）で選ぶ数値入力欄。
class _MinutesField extends StatelessWidget {
  const _MinutesField({
    required this.label,
    required this.controller,
    required this.min,
    required this.max,
    this.suffixText,
  });

  final String label;
  final TextEditingController controller;
  final int min;
  final int max;
  final String? suffixText;

  Future<void> _openPicker(BuildContext context) async {
    final current = int.tryParse(controller.text) ?? min;
    final initialIndex = (current - min).clamp(0, max - min);
    var selected = min + initialIndex;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: 260,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('完了'),
                    ),
                  ],
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController:
                        FixedExtentScrollController(initialItem: initialIndex),
                    itemExtent: 36,
                    onSelectedItemChanged: (index) => selected = min + index,
                    children: [
                      for (var v = min; v <= max; v++)
                        Center(child: Text('$v${suffixText ?? ''}')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.text = selected.toString();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return InkWell(
          onTap: () => _openPicker(context),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontSize: 12),
              suffixText: suffixText,
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            child: Text(value.text),
          ),
        );
      },
    );
  }
}

/// 選択肢1件分（ラベル・アセットパス・試聴用コールバック）を表す共通インターフェース。
class _SoundOption {
  const _SoundOption(this.label, this.assetPath);
  final String label;
  final String? assetPath;
}

/// ラベルをタップで選択、試聴ボタンをタップで選択前に音を聴けるリストをボトムシートで表示する。
Future<T?> _showSoundPicker<T>({
  required BuildContext context,
  required String title,
  required List<T> values,
  required T selected,
  required _SoundOption Function(T) toOption,
  required ValueChanged<String> onPreview,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                title,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final v in values)
              ListTile(
                title: Text(toOption(v).label),
                selected: v == selected,
                onTap: () => Navigator.of(sheetContext).pop(v),
                trailing: IconButton(
                  onPressed: toOption(v).assetPath == null
                      ? null
                      : () => onPreview(toOption(v).assetPath!),
                  icon: const Icon(Icons.play_arrow_rounded),
                  tooltip: '試聴',
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _BgmDropdown extends StatelessWidget {
  const _BgmDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onPreview,
  });

  final String label;
  final PomodoroBgm value;
  final ValueChanged<PomodoroBgm> onChanged;
  final ValueChanged<String> onPreview;

  Future<void> _openPicker(BuildContext context) async {
    final selected = await _showSoundPicker<PomodoroBgm>(
      context: context,
      title: label,
      values: PomodoroBgm.values,
      selected: value,
      toOption: (b) => _SoundOption(b.label, b.assetPath),
      onPreview: onPreview,
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openPicker(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        child: Row(
          children: [
            Expanded(child: Text(value.label)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class _ChimeDropdown extends StatelessWidget {
  const _ChimeDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onPreview,
  });

  final String label;
  final PomodoroChime value;
  final ValueChanged<PomodoroChime> onChanged;
  final ValueChanged<String> onPreview;

  Future<void> _openPicker(BuildContext context) async {
    final selected = await _showSoundPicker<PomodoroChime>(
      context: context,
      title: label,
      values: PomodoroChime.values,
      selected: value,
      toOption: (c) => _SoundOption(c.label, c.assetPath),
      onPreview: onPreview,
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openPicker(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        child: Row(
          children: [
            Expanded(child: Text(value.label)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
