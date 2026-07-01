import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/widgets/task_detail/quadrant_selector.dart';

typedef QuickCreateResult = ({
  String title,
  int durationMinutes,
  Quadrant quadrant,
});

/// 空スロットタップから呼び出される予定作成シート。
/// 結果は [QuickCreateResult]。キャンセル時は null。
class QuickCreateSheet extends StatefulWidget {
  const QuickCreateSheet({super.key, required this.initialStart});

  final DateTime initialStart;

  @override
  State<QuickCreateSheet> createState() => _QuickCreateSheetState();
}

class _QuickCreateSheetState extends State<QuickCreateSheet> {
  final _controller = TextEditingController();
  int _durationMinutes = 60;
  Quadrant _selectedQuadrant = Quadrant.urgentImportant;

  static const _durations = [15, 30, 45, 60, 90, 120, 180];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(int m) {
    if (m < 60) return '$m分';
    if (m % 60 == 0) return '${m ~/ 60}時間';
    return '${m ~/ 60}時間${m % 60}分';
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    Navigator.pop<QuickCreateResult>(context, (
      title: title,
      durationMinutes: _durationMinutes,
      quadrant: _selectedQuadrant,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final startFmt = DateFormat('M月d日 (E) HH:mm', 'ja_JP');

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
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _durationMinutes,
                  items: _durations
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(_formatDuration(m)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _durationMinutes = v);
                  },
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
                FilledButton(onPressed: _submit, child: const Text('保存')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
