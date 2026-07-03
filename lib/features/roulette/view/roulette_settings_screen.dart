import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_manager/features/roulette/model/reward_config.dart';
import 'package:task_manager/features/roulette/widgets/roulette_board.dart';
import 'package:task_manager/features/user_settings/model/user_settings.dart';
import 'package:task_manager/features/user_settings/viewmodel/user_settings_viewmodel.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:task_manager/widgets/message_guard.dart';

/// ルーレットの設定画面。週単位の出現設定とご褒美リストを入力すると、盤面プレビューがその場で生成される。
class RouletteSettingsScreen extends ConsumerStatefulWidget {
  const RouletteSettingsScreen({super.key});

  @override
  ConsumerState<RouletteSettingsScreen> createState() =>
      _RouletteSettingsScreenState();
}

class _RouletteSettingsScreenState
    extends ConsumerState<RouletteSettingsScreen> {
  late final TextEditingController _wCtrl;
  late final TextEditingController _jCtrl;
  late final TextEditingController _cCtrl;
  late final List<TextEditingController> _jackpotCtrls;
  late final List<TextEditingController> _chuCtrls;
  late final List<TextEditingController> _shoCtrls;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _wCtrl = TextEditingController();
    _jCtrl = TextEditingController();
    _cCtrl = TextEditingController();
    _jackpotCtrls = [];
    _chuCtrls = [];
    _shoCtrls = [];
    // 週設定の変更で盤面プレビューを更新する。
    _wCtrl.addListener(() => setState(() {}));
    _jCtrl.addListener(() => setState(() {}));
    _cCtrl.addListener(() => setState(() {}));
  }

  void _initFrom(UserSettings s) {
    if (_initialized) return;
    _initialized = true;
    _wCtrl.text = _trimNum(s.weeklyTaskCount);
    _jCtrl.text = _trimNum(s.weeklyJackpotCount);
    _cCtrl.text = _trimNum(s.weeklyChuCount);
    _fillSlots(_jackpotCtrls, s.jackpotRewards);
    _fillSlots(_chuCtrls, s.chuRewards);
    _fillSlots(_shoCtrls, s.shoRewards);
  }

  void _fillSlots(List<TextEditingController> ctrls, List<String> values) {
    final count = values.length > RewardConfig.rewardSlotsPerTier
        ? values.length
        : RewardConfig.rewardSlotsPerTier;
    for (var i = 0; i < count; i++) {
      ctrls.add(
        TextEditingController(text: i < values.length ? values[i] : ''),
      );
    }
  }

  String _trimNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  @override
  void dispose() {
    _wCtrl.dispose();
    _jCtrl.dispose();
    _cCtrl.dispose();
    for (final c in [..._jackpotCtrls, ..._chuCtrls, ..._shoCtrls]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _w => double.tryParse(_wCtrl.text.trim()) ?? 0;
  double get _j => double.tryParse(_jCtrl.text.trim()) ?? 0;
  double get _c => double.tryParse(_cCtrl.text.trim()) ?? 0;

  List<String> _collect(List<TextEditingController> ctrls) => ctrls
      .map((c) => c.text.trim())
      .where((t) => t.isNotEmpty)
      .toList(growable: false);

  Future<void> _save() async {
    final err = RewardConfig.validateRouletteInput(
      weeklyTaskCount: _w,
      weeklyJackpotCount: _j,
      weeklyChuCount: _c,
    );
    if (err != null) {
      showAppSnackBar(context, SnackBar(content: Text(err)));
      return;
    }
    final vm = ref.read(userSettingsProvider.notifier);
    final base = ref.read(userSettingsProvider).settings;
    vm.update(
      base.copyWith(
        weeklyTaskCount: _w,
        weeklyJackpotCount: _j,
        weeklyChuCount: _c,
        jackpotRewards: _collect(_jackpotCtrls),
        chuRewards: _collect(_chuCtrls),
        shoRewards: _collect(_shoCtrls),
      ),
    );
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
    ref.listen<UserSettingsState>(userSettingsProvider, (prev, next) {
      if (!next.isLoading && (prev == null || prev.isLoading)) {
        _initFrom(next.settings);
      }
    });
    if (!state.isLoading && !_initialized) {
      _initFrom(state.settings);
    }

    final text = Theme.of(context).textTheme;
    final inputErr = RewardConfig.validateRouletteInput(
      weeklyTaskCount: _w,
      weeklyJackpotCount: _j,
      weeklyChuCount: _c,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('ルーレット設定'),
        actions: [
          state.isSaving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text(
                    '保存',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
        ],
      ),
      body: MessageGuard(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionHeader('① 出現確率の設定（単位：１週間）'),
                  const SizedBox(height: 8),
                  _buildWeeklyFields(),
                  const SizedBox(height: 16),
                  _buildPreview(text, inputErr),
                  const SizedBox(height: 24),
                  _SectionHeader('② ご褒美の内容'),
                  const SizedBox(height: 4),
                  Text('当たった区分のご褒美からランダムに1つ選ばれます。', style: text.bodySmall),
                  const SizedBox(height: 8),
                  _RewardGroup(
                    title: '大当たり',
                    color: RouletteBoard.colorFor(
                      RouletteCategory.jackpot,
                      Theme.of(context).colorScheme,
                    ),
                    controllers: _jackpotCtrls,
                  ),
                  _RewardGroup(
                    title: '中当たり',
                    color: RouletteBoard.colorFor(
                      RouletteCategory.chu,
                      Theme.of(context).colorScheme,
                    ),
                    controllers: _chuCtrls,
                  ),
                  _RewardGroup(
                    title: '小当たり（即時OK・チケットにはなりません）',
                    color: RouletteBoard.colorFor(
                      RouletteCategory.sho,
                      Theme.of(context).colorScheme,
                    ),
                    controllers: _shoCtrls,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
      ),
    );
  }

  Widget _buildPreview(TextTheme text, String? inputErr) {
    if (inputErr != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          inputErr,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      );
    }
    final probs = RewardConfig.probabilitiesFor(
      weeklyTaskCount: _w,
      weeklyJackpotCount: _j,
      weeklyChuCount: _c,
    );
    final cells = RewardConfig.boardCells(probs);
    return Column(
      children: [
        Center(child: RouletteBoard(cells: cells, size: 220)),
        const SizedBox(height: 12),
        Center(child: RouletteLegend(probabilities: probs)),
        if (probs.jackpotClamped) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '大当たりが多すぎます（上限${(RewardConfig.jackpotCap * 100).toStringAsFixed(0)}%でクランプ）。'
              '特別感が薄れるため J を小さく、または W を大きくしてください。',
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
        if (probs.chuClamped) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '中当たりが多すぎます。残り確率を超える分は自動で調整されます。',
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWeeklyFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 24) / 3;
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _NumberField(controller: _wCtrl, label: 'タスク予定数'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                controller: _jCtrl,
                label: '大当たり数',
                allowDecimal: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                controller: _cCtrl,
                label: '中当たり数',
                allowDecimal: true,
              ),
            ),
          ],
        );
        if (width >= 92) return row;
        return Column(
          children: [
            _NumberField(controller: _wCtrl, label: 'タスク予定数'),
            const SizedBox(height: 12),
            _NumberField(
              controller: _jCtrl,
              label: '大当たり数',
              allowDecimal: true,
            ),
            const SizedBox(height: 12),
            _NumberField(
              controller: _cCtrl,
              label: '中当たり数',
              allowDecimal: true,
            ),
          ],
        );
      },
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

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.allowDecimal = false,
  });

  final TextEditingController controller;
  final String label;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              allowDecimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
            ),
          ],
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}

/// 1区分のご褒美入力（複数枠）。
class _RewardGroup extends StatelessWidget {
  const _RewardGroup({
    required this.title,
    required this.color,
    required this.controllers,
  });

  final String title;
  final Color color;
  final List<TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...List.generate(
            controllers.length,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: controllers[i],
                decoration: InputDecoration(
                  hintText: 'ご褒美 ${i + 1}',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                maxLength: 40,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
