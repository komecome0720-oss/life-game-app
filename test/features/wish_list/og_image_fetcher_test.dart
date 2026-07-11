import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager/features/wish_list/data/og_image_fetcher.dart';

final _fakeImageBytes = Uint8List.fromList(List<int>.generate(16, (i) => i));

void main() {
  group('OgImageFetcher.fetchImageBytes', () {
    test('og:image がある HTML → 画像バイトが返る', () async {
      final fetcher = OgImageFetcher(
        clientFactory: () => MockClient((request) async {
          if (request.url.path == '/item') {
            return http.Response(
              '<html><head>'
              '<meta property="og:image" content="https://img.example.com/pic.jpg">'
              '</head></html>',
              200,
            );
          }
          if (request.url.toString() == 'https://img.example.com/pic.jpg') {
            return http.Response.bytes(
              _fakeImageBytes,
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final result = await fetcher.fetchImageBytes('https://shop.example.com/item');

      expect(result, _fakeImageBytes);
    });

    test('og:image が相対URL → ベースURLで絶対化されて画像GETされる', () async {
      final fetcher = OgImageFetcher(
        clientFactory: () => MockClient((request) async {
          if (request.url.path == '/item') {
            return http.Response(
              '<html><head>'
              '<meta property="og:image" content="/images/pic.jpg">'
              '</head></html>',
              200,
            );
          }
          if (request.url.toString() == 'https://shop.example.com/images/pic.jpg') {
            return http.Response.bytes(
              _fakeImageBytes,
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final result = await fetcher.fetchImageBytes('https://shop.example.com/item');

      expect(result, _fakeImageBytes);
    });

    test('og:image なし → null', () async {
      final fetcher = OgImageFetcher(
        clientFactory: () => MockClient((request) async {
          return http.Response('<html><head></head></html>', 200);
        }),
      );

      final result = await fetcher.fetchImageBytes('https://shop.example.com/item');

      expect(result, isNull);
    });

    test('HTML GET が 403（Amazon想定）→ null', () async {
      final fetcher = OgImageFetcher(
        clientFactory: () => MockClient((request) async {
          return http.Response('forbidden', 403);
        }),
      );

      final result = await fetcher.fetchImageBytes('https://www.amazon.co.jp/dp/xxx');

      expect(result, isNull);
    });

    test('画像の Content-Type が text/html → null', () async {
      final fetcher = OgImageFetcher(
        clientFactory: () => MockClient((request) async {
          if (request.url.path == '/item') {
            return http.Response(
              '<html><head>'
              '<meta property="og:image" content="https://img.example.com/pic.jpg">'
              '</head></html>',
              200,
            );
          }
          return http.Response(
            '<html>not an image</html>',
            200,
            headers: {'content-type': 'text/html'},
          );
        }),
      );

      final result = await fetcher.fetchImageBytes('https://shop.example.com/item');

      expect(result, isNull);
    });

    test('スキームなしURL（example.com/item）→ https 前置で成功', () async {
      final fetcher = OgImageFetcher(
        clientFactory: () => MockClient((request) async {
          expect(request.url.scheme, 'https');
          if (request.url.path == '/item') {
            return http.Response(
              '<html><head>'
              '<meta property="og:image" content="https://img.example.com/pic.jpg">'
              '</head></html>',
              200,
            );
          }
          if (request.url.toString() == 'https://img.example.com/pic.jpg') {
            return http.Response.bytes(
              _fakeImageBytes,
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final result = await fetcher.fetchImageBytes('example.com/item');

      expect(result, _fakeImageBytes);
    });
  });
}
