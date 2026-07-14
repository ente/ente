import "dart:io" show File;
import "dart:typed_data" show Uint8List;

import "package:image/image.dart" as image;
import "package:logging/logging.dart";

final _logger = Logger("ImageDecodeUtil");

Future<Uint8List?> createSafeJpegDecodeFallbackBytes({
  required String imagePath,
}) async {
  final imageData = await File(imagePath).readAsBytes();
  return _createSafeJpegDecodeFallbackBytesFromData(imageData);
}

Uint8List? _createSafeJpegDecodeFallbackBytesFromData(Uint8List imageData) {
  try {
    final decoded = image.decodeImage(imageData);
    if (decoded == null) {
      return null;
    }
    return Uint8List.fromList(image.encodeJpg(decoded, quality: 95));
  } catch (e) {
    final firstLine = e.toString().split("\n").first.trim();
    _logger.warning(
      firstLine.isEmpty
          ? "Safe JPEG conversion failed"
          : "Safe JPEG conversion failed: $firstLine",
    );
    return null;
  }
}
