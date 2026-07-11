import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

const _userAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

const _maxImageBytes = 10 * 1024 * 1024;

/// ショップページURLから OGP 画像の生バイトを取得する。
/// 失敗はすべて null（例外を外に漏らさない）。
class OgImageFetcher {
  OgImageFetcher({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  Future<Uint8List?> fetchImageBytes(String pageUrl) async {
    final pageUri = _normalize(pageUrl);
    if (pageUri == null) return null;

    try {
      final imageUri = await _fetchOgImageUri(pageUri);
      if (imageUri == null) return null;
      return await _fetchImageBytes(imageUri);
    } catch (_) {
      return null;
    }
  }

  Uri? _normalize(String rawUrl) {
    var normalized = rawUrl.trim();
    if (normalized.isEmpty) return null;
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri;
  }

  Future<Uri?> _fetchOgImageUri(Uri pageUri) async {
    final client = _clientFactory();
    try {
      final response = await client
          .get(
            pageUri,
            headers: const {
              'User-Agent': _userAgent,
              'Accept': 'text/html',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final document = html_parser.parse(response.body);
      final content = _findImageContent(document);
      if (content == null || content.isEmpty) return null;

      return Uri.tryParse(content) != null
          ? pageUri.resolveUri(Uri.parse(content))
          : null;
    } finally {
      client.close();
    }
  }

  String? _findImageContent(Document document) {
    final selectors = [
      'meta[property="og:image:secure_url"]',
      'meta[property="og:image"]',
      'meta[name="twitter:image"]',
    ];
    for (final selector in selectors) {
      final el = document.querySelector(selector);
      final content = el?.attributes['content'];
      if (content != null && content.trim().isNotEmpty) {
        return content.trim();
      }
    }
    final linkEl = document.querySelector('link[rel="image_src"]');
    final href = linkEl?.attributes['href'];
    if (href != null && href.trim().isNotEmpty) {
      return href.trim();
    }
    return null;
  }

  Future<Uint8List?> _fetchImageBytes(Uri imageUri) async {
    final client = _clientFactory();
    try {
      final response = await client
          .get(imageUri, headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.startsWith('image/')) return null;

      final bytes = response.bodyBytes;
      if (bytes.length > _maxImageBytes) return null;

      return bytes;
    } finally {
      client.close();
    }
  }
}

final ogImageFetcherProvider = Provider<OgImageFetcher>((ref) => OgImageFetcher());
