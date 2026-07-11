import 'package:flutter/material.dart';
import 'package:task_manager/utils/app_messenger.dart';
import 'package:url_launcher/url_launcher.dart';

/// ショップURL等を端末のデフォルトブラウザ（外部アプリ）で開く。
/// `canLaunchUrl` は使わない（iOSでは LSApplicationQueriesSchemes 未登録だと
/// https でも false を返すため）。`launchUrl` を直接呼び、失敗を扱う。
Future<void> openExternalUrl(BuildContext context, String rawUrl) async {
  final trimmed = rawUrl.trim();
  var normalized = trimmed;
  if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
    normalized = 'https://$normalized';
  }

  final uri = Uri.tryParse(normalized);
  var succeeded = false;
  if (uri != null) {
    try {
      succeeded = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      succeeded = false;
    }
  }

  if (!succeeded && context.mounted) {
    showAppSnackBar(
      context,
      const SnackBar(content: Text('リンクを開けませんでした')),
    );
  }
}
