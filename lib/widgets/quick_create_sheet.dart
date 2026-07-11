import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/widgets/prediction_chip_sheet.dart';
import 'package:task_manager/widgets/prediction_chip_settings_dialog.dart';
import 'package:task_manager/widgets/task_detail/quadrant_selector.dart';

/// [durationMinutes] は予測宣言チップで選ばれた分数（確定仕様6: 空きスロットからの
/// 予定作成＝宣言）。終了時刻はこの値から算出され、そのまま宣言値として保存される。
typedef QuickCreateResult = ({
  String title,
  int durationMinutes,
  Quadrant quadrant,
});

/// 空スロットタップから呼び出される予定作成シート。
/// 予測時間チップは必須入力（未選択の間は保存不可）。結果は [QuickCreateResult]。
/// キャンセル時は null。
class QuickCreateSheet extends ConsumerStatefulWidget {
  const QuickCreateSheet({super.key, required this.initialStart});

  final DateTime initialStart;

  @override
  ConsumerState<QuickCreateSheet> createState() => _QuickCreateSheetState();
}

class _QuickCreateSheetState extends ConsumerState<QuickCreateSheet> {
  final _controller = TextEditingController();
  int? _durationMinutes;
  Quadrant _selectedQuadrant = Quadrant.urgentImportant;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openFreeInput() async {
    final minutes = await showPredictionFreeInputDialog(context);
    if (minutes != null && mounted) {
      setState(() => _durationMinutes = minutes);
    }
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const PredictionChipSettingsDialog(),
    );
  }

  void _submit() {
    final title = _controller.text.trim();
    final minutes = _durationMinutes;
    if (title.isEmpty || minutes == null) return;
    Navigator.pop<QuickCreateResult>(context, (
      title: title,
      durationMinutes: minutes,
      quadrant: _selectedQuadrant,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final startFmt = DateFormat('M月d日 (E) HH:mm', 'ja_JP');
    final presets = ref.watch(
      userSettingsProvider.select((s) => s.settings.predictionChipMinutes),
    );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.event, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '予定を追加',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'タイトル',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Text('領域', style: text.labelMedium),
            const SizedBox(height: 8),
            QuadrantSelector(
              selected: _selectedQuadrant,
              onSelect: (q) => setState(() => _selectedQuadrant = q),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.schedule, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    startFmt.format(widget.initialStart),
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '予測時間（終了時刻はこれで決まります）',
                    style: text.labelMedium,
                  ),
                ),
                IconButton(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'プリセットを編集',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in presets)
                  ChoiceChip(
                    label: Text(formatPredictionMinutes(m)),
                    selected: _durationMinutes == m,
                    onSelected: (_) => setState(() => _durationMinutes = m),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.edit, size: 18),
                  label: Text(
                    _durationMinutes != null &&
                            !presets.contains(_durationMinutes)
                        ? formatPredictionMinutes(_durationMinutes!)
                        : '自由入力',
                  ),
                  onPressed: _openFreeInput,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _durationMinutes != null ? _submit : null,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
