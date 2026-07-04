// 一時プレビュー用エントリ（見た目確認用・確認後に削除する）。
// タイマーUIの見た目と「スタート！」演出を Firebase 抜きで確認する。
import 'package:flutter/material.dart';

import 'package:task_manager/models/calendar_task.dart';
import 'package:task_manager/widgets/task_event_detail_sheet.dart';

void main() {
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timer Preview',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const _PreviewHome(),
    );
  }
}

class _PreviewHome extends StatefulWidget {
  const _PreviewHome();

  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  void _openSheet() {
    final now = DateTime.now();
    final task = CalendarTask(
      id: 'preview-1',
      title: 'サンプルタスク',
      start: now,
      end: now.add(const Duration(minutes: 60)),
      rewardYen: 1500,
    );
    showTaskEventDetailSheet(
      context: context,
      task: task,
      predictedMinutes: 60,
      expectedRewardYen: 1500,
      onComplete:
          ({required predictedMinutes, required actualMinutes}) async {},
      onTimerStart: () async {},
      onPauseAndSave:
          ({required predictedMinutes, required actualMinutes}) async {},
    );
  }

  // 完了済みタスクの実績カード（時間予測精度ゲーム）の見た目確認用。
  void _openCompletedSheet() {
    final now = DateTime.now();
    final task = CalendarTask(
      id: 'preview-2',
      title: '完了済みサンプル',
      start: now.subtract(const Duration(minutes: 45)),
      end: now,
      rewardYen: 1500,
      isCompleted: true,
      completedAt: now,
      completedRewardYen: 1125,
      predictedMinutes: 60,
      actualMinutes: 45,
    );
    showTaskEventDetailSheet(
      context: context,
      task: task,
      predictedMinutes: 60,
      expectedRewardYen: 1500,
      onComplete:
          ({required predictedMinutes, required actualMinutes}) async {},
      onRevert: () async => true,
    );
  }

  @override
  void initState() {
    super.initState();
    // 起動直後に自動でシートを開く（見た目確認用）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _openSheet());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timer Preview')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: _openSheet,
              child: const Text('詳細シートを開く'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _openCompletedSheet,
              child: const Text('完了済みシートを開く'),
            ),
          ],
        ),
      ),
    );
  }
}
