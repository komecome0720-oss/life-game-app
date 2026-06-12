import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/todo/providers/todo_providers.dart';
import 'package:task_manager/features/todo/viewmodel/todo_matrix_viewmodel.dart';
import 'package:task_manager/features/todo/widgets/calendar_drop_bar.dart';
import 'package:task_manager/features/todo/widgets/todo_quadrant.dart';
import 'package:task_manager/widgets/message_guard.dart';

/// Eisenhower Matrix 形式の ToDo 一覧画面。
class TodoMatrixScreen extends ConsumerWidget {
  const TodoMatrixScreen({super.key});

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    var selected = Quadrant.urgentImportant;

    final result = await showDialog<({String title, Quadrant quadrant})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            void submit() {
              Navigator.pop(
                ctx,
                (title: controller.text, quadrant: selected),
              );
            }

            Widget chip(Quadrant q) {
              final isSelected = selected == q;
              final scheme = Theme.of(ctx).colorScheme;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => selected = q),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(color: scheme.primary, width: 1.5)
                          : null,
                    ),
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        q.label,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: isSelected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              title: const Text('ToDo を追加'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(
                      labelText: 'タイトル',
                      hintText: '例: 企画書のたたきを作る',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '領域',
                    style: Theme.of(ctx).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      chip(Quadrant.notUrgentImportant),
                      const SizedBox(width: 8),
                      chip(Quadrant.urgentImportant),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      chip(Quadrant.notUrgentNotImportant),
                      const SizedBox(width: 8),
                      chip(Quadrant.urgentNotImportant),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: submit,
                  child: const Text('追加'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null) return;
    final title = result.title.trim();
    if (title.isEmpty) return;
    await ref
        .read(todoMatrixViewModelProvider)
        .createTodo(title, quadrant: result.quadrant);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final todosAsync = ref.watch(todosStreamProvider);
    final vm = ref.read(todoMatrixViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ToDo'),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'todo_fab',
        onPressed: () => _showAddDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: MessageGuard(
        child: SafeArea(
        child: todosAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('エラー: $e')),
          data: (tasks) {
            // 中央十字矢印（軸ラベルはブロックの外に出すため、芯のみ）
            const double centerArrowWidth = 12; // 縦矢印（重要度）の幅
            const double centerArrowHeight = 12; // 横矢印（緊急度）の高さ
            // ブロックの外に置く軸ラベルの帯
            const double topLabelHeight = 20; // 上: 重要度（横書き）
            const double leftLabelWidth = 20; // 左: 緊急度（縦書き）

            final axisColor = scheme.primary;
            final labelStyle = text.labelMedium?.copyWith(
              color: axisColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            );

            return Stack(
              children: [
                // ── マトリクス本体 ───────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Column(
                    children: [
                      // 重要度（上向き矢印の末端 = 上端の外側）に横書き
                      SizedBox(
                        height: topLabelHeight,
                        child: Row(
                          children: [
                            const SizedBox(width: leftLabelWidth),
                            Expanded(
                              child: Center(
                                child: Text('重要度', style: labelStyle),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            // 緊急度（ブロック左端外側）に縦書き（1文字ずつ縦に）
                            SizedBox(
                              width: leftLabelWidth,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final c in '緊急度'.split(''))
                                      Text(c, style: labelStyle),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Stack(
                                children: [
                                  // 2x2 象限（上=重要、右=緊急）
                                  Column(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            // 左上: ×緊急・重要（2 / 黄色）
                                            Expanded(
                                              child: TodoQuadrant(
                                                quadrant:
                                                    Quadrant.notUrgentImportant,
                                                tasks: vm.filterByQuadrant(
                                                    tasks,
                                                    Quadrant
                                                        .notUrgentImportant),
                                                backgroundColor: Quadrant
                                                    .notUrgentImportant
                                                    .backgroundColor(scheme),
                                                accentColor: Quadrant
                                                    .notUrgentImportant
                                                    .accentColor(scheme),
                                              ),
                                            ),
                                            // 右上: 緊急・重要（1 / 赤）
                                            Expanded(
                                              child: TodoQuadrant(
                                                quadrant:
                                                    Quadrant.urgentImportant,
                                                tasks: vm.filterByQuadrant(
                                                    tasks,
                                                    Quadrant.urgentImportant),
                                                backgroundColor: Quadrant
                                                    .urgentImportant
                                                    .backgroundColor(scheme),
                                                accentColor: Quadrant
                                                    .urgentImportant
                                                    .accentColor(scheme),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            // 左下: ×緊急・×重要（4 / 灰色）
                                            Expanded(
                                              child: TodoQuadrant(
                                                quadrant: Quadrant
                                                    .notUrgentNotImportant,
                                                tasks: vm.filterByQuadrant(
                                                    tasks,
                                                    Quadrant
                                                        .notUrgentNotImportant),
                                                backgroundColor: Quadrant
                                                    .notUrgentNotImportant
                                                    .backgroundColor(scheme),
                                                accentColor: Quadrant
                                                    .notUrgentNotImportant
                                                    .accentColor(scheme),
                                              ),
                                            ),
                                            // 右下: 緊急・×重要（3 / 水色）
                                            Expanded(
                                              child: TodoQuadrant(
                                                quadrant:
                                                    Quadrant.urgentNotImportant,
                                                tasks: vm.filterByQuadrant(
                                                    tasks,
                                                    Quadrant
                                                        .urgentNotImportant),
                                                backgroundColor: Quadrant
                                                    .urgentNotImportant
                                                    .backgroundColor(scheme),
                                                accentColor: Quadrant
                                                    .urgentNotImportant
                                                    .accentColor(scheme),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  // 中央 縦矢印（重要度: 上向き）
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Center(
                                        child: SizedBox(
                                          width: centerArrowWidth,
                                          height: double.infinity,
                                          child: CustomPaint(
                                            painter: _AxisArrowPainter(
                                              color: axisColor.withValues(
                                                  alpha: 0.55),
                                              direction:
                                                  _AxisArrowDirection.up,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 中央 横矢印（緊急度: 右向き）
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Center(
                                        child: SizedBox(
                                          width: double.infinity,
                                          height: centerArrowHeight,
                                          child: CustomPaint(
                                            painter: _AxisArrowPainter(
                                              color: axisColor.withValues(
                                                  alpha: 0.55),
                                              direction:
                                                  _AxisArrowDirection.right,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (tasks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '右下の＋ボタンから ToDo を追加しましょう',
                            style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),

                // ── 上部のカレンダー追加バー（長押し中のみ表示） ───
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: CalendarDropBar(
                    onSwitchToCalendar: () {
                      final notifier =
                          ref.read(mainTabIndexProvider.notifier);
                      // ホームタブ（index=0）に切替
                      notifier.set(0);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      ),
    );
  }
}

enum _AxisArrowDirection { up, right, left }

/// 軸用の三角形矢印。基部側が細く先端側が太くなる。
class _AxisArrowPainter extends CustomPainter {
  _AxisArrowPainter({required this.color, required this.direction});
  final Color color;
  final _AxisArrowDirection direction;

  static const double _arrowHead = 8;
  static const double _maxThick = 5;
  static const double _minThick = 0.6;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final path = Path();

    switch (direction) {
      case _AxisArrowDirection.up:
        final cx = size.width / 2;
        final shaftTopY = _arrowHead;
        final headHalf = _arrowHead / 2 + 1;
        path.moveTo(cx - _minThick / 2, size.height);
        path.lineTo(cx - _maxThick / 2, shaftTopY);
        path.lineTo(cx - headHalf, shaftTopY);
        path.lineTo(cx, 0);
        path.lineTo(cx + headHalf, shaftTopY);
        path.lineTo(cx + _maxThick / 2, shaftTopY);
        path.lineTo(cx + _minThick / 2, size.height);
        path.close();
        break;
      case _AxisArrowDirection.right:
        final cy = size.height / 2;
        final shaftRightX = size.width - _arrowHead;
        final headHalf = _arrowHead / 2 + 1;
        path.moveTo(0, cy - _minThick / 2);
        path.lineTo(shaftRightX, cy - _maxThick / 2);
        path.lineTo(shaftRightX, cy - headHalf);
        path.lineTo(size.width, cy);
        path.lineTo(shaftRightX, cy + headHalf);
        path.lineTo(shaftRightX, cy + _maxThick / 2);
        path.lineTo(0, cy + _minThick / 2);
        path.close();
        break;
      case _AxisArrowDirection.left:
        final cy = size.height / 2;
        final shaftLeftX = _arrowHead;
        final headHalf = _arrowHead / 2 + 1;
        path.moveTo(size.width, cy - _minThick / 2);
        path.lineTo(shaftLeftX, cy - _maxThick / 2);
        path.lineTo(shaftLeftX, cy - headHalf);
        path.lineTo(0, cy);
        path.lineTo(shaftLeftX, cy + headHalf);
        path.lineTo(shaftLeftX, cy + _maxThick / 2);
        path.lineTo(size.width, cy + _minThick / 2);
        path.close();
        break;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_AxisArrowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.direction != direction;
}
