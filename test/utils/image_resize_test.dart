import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:task_manager/utils/image_resize.dart';

void main() {
  group('resizeToJpegSync', () {
    test('大きい画像は長辺800以下に縮小され、JPEGとしてデコード可能', () {
      final source = img.Image(width: 1600, height: 1200);
      img.fill(source, color: img.ColorRgb8(200, 100, 50));
      final bytes = img.encodePng(source);

      final result = resizeToJpegSync(bytes);

      expect(result, isNotNull);
      final decoded = img.decodeJpg(result!);
      expect(decoded, isNotNull);
      expect(decoded!.width <= 800, isTrue);
      expect(decoded.height <= 800, isTrue);
      expect(decoded.width, 800);
      expect(decoded.height, 600);
    });

    test('小さい画像は拡大されない', () {
      final source = img.Image(width: 400, height: 300);
      img.fill(source, color: img.ColorRgb8(10, 20, 30));
      final bytes = img.encodePng(source);

      final result = resizeToJpegSync(bytes);

      expect(result, isNotNull);
      final decoded = img.decodeJpg(result!);
      expect(decoded, isNotNull);
      expect(decoded!.width, 400);
      expect(decoded.height, 300);
    });

    test('壊れたバイト列は null を返す', () {
      final garbage = Uint8List.fromList(
        List<int>.generate(32, (i) => (i * 7) % 256),
      );
      final result = resizeToJpegSync(garbage);
      expect(result, isNull);
    });
  });
}
