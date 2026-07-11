import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 長辺 [maxDimension] に収まるよう縮小し JPEG（[quality]）で再エンコードする。
/// デコードできないバイト列の場合は null を返す。
Uint8List? resizeToJpegSync(
  Uint8List bytes, {
  int maxDimension = 800,
  int quality = 80,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final resized = (decoded.width > maxDimension || decoded.height > maxDimension)
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxDimension : null,
          height: decoded.height > decoded.width ? maxDimension : null,
        )
      : decoded;

  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}

/// compute() のコールバックは単一引数必須のため、既定値固定の単一引数
/// トップレベル関数を挟む。
Uint8List? _resizeEntry(Uint8List bytes) => resizeToJpegSync(bytes);

/// メインアイソレートを塞がないよう別アイソレートでデコード・再エンコードする。
Future<Uint8List?> resizeToJpeg(Uint8List bytes) => compute(_resizeEntry, bytes);
