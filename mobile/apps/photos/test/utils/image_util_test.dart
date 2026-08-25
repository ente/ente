import "dart:ui" as ui;

import "package:flutter/foundation.dart";
import "package:flutter/painting.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/utils/image_util.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image sourceImage;

  setUp(() async {
    sourceImage = await createTestImage(width: 3, height: 2, cache: false);
  });

  tearDown(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    sourceImage.dispose();
  });

  test(
    "getImageSize returns dimensions without retaining an image handle",
    () async {
      final initialHandleCount = sourceImage
          .debugGetOpenHandleStackTraces()!
          .length;

      final size = await getImageSize(_TestImageProvider(sourceImage));

      expect(size, const Size(3, 2));

      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await Future<void>.delayed(Duration.zero);

      expect(
        sourceImage.debugGetOpenHandleStackTraces()!.length,
        initialHandleCount,
      );
    },
  );
}

class _TestImageProvider extends ImageProvider<_TestImageProvider> {
  _TestImageProvider(this.image);

  final ui.Image image;

  @override
  Future<_TestImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_TestImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _TestImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
    );
  }
}
