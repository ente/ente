import 'dart:typed_data';

import 'package:exif_reader/exif_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:photos/utils/image_util.dart';

void main() {
  group('getImageDimensions', () {
    test(
      'returns display-oriented dimensions for rotated EXIF images',
      () async {
        final source = image.Image(width: 4, height: 2);
        source.exif.imageIfd.orientation = 6;
        final encoded = Uint8List.fromList(image.encodeJpg(source));
        final exif = await readExifFromBytes(encoded);

        expect(exif.tags['Image Orientation']?.printable, 'Rotated 90 CW');

        final dimensions = await getImageDimensions(imageBytes: encoded);

        expect(dimensions, isNotNull);
        expect(dimensions!.width, 2);
        expect(dimensions.height, 4);
      },
    );
  });
}
