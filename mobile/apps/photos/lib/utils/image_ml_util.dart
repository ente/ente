import "dart:async";
import "dart:io" show File, Platform;
import "dart:math" show exp, max, min, pi;
import "dart:typed_data" show Float32List, Uint8List;
import "dart:ui";

import "package:exif_reader/exif_reader.dart";
import 'package:flutter/painting.dart' as paint show decodeImageFromList;
import "package:flutter_image_compress/flutter_image_compress.dart";
import "package:image/image.dart" as img;
import "package:logging/logging.dart";
import 'package:ml_linalg/linalg.dart';
import "package:photos/models/ml/face/box.dart";
import "package:photos/models/ml/face/dimension.dart";
import 'package:photos/services/machine_learning/face_ml/face_alignment/alignment_result.dart';
import 'package:photos/services/machine_learning/face_ml/face_alignment/similarity_transform.dart';
import 'package:photos/services/machine_learning/face_ml/face_detection/detection.dart';
import 'package:photos/services/machine_learning/face_ml/face_filtering/blur_detection_service.dart';
import 'package:photos/utils/image_util.dart';

/// All of the functions in this file are helper functions for using inside an isolate.
/// Don't use them outside of a isolate, unless you are okay with UI jank!!!!

final _logger = Logger("ImageMlUtil");

/// These are 8 bit unsigned integers in range 0-255 for each RGB channel
typedef RGB = (int, int, int);

const gaussianKernelSize = 5;
const gaussianKernelRadius = gaussianKernelSize ~/ 2;
const gaussianSigma = 10.0;
final List<List<double>> gaussianKernel = create2DGaussianKernel(
  gaussianKernelSize,
  gaussianSigma,
);

const maxKernelSize = gaussianKernelSize;
const maxKernelRadius = maxKernelSize ~/ 2;

// Face thumbnail compression constants
const int _faceThumbnailCompressionQuality = 90;
const int _faceThumbnailMinDimension = 512;

class DecodedImage {
  final Dimensions dimensions;
  final Image? image;
  final Uint8List? rawRgbaBytes;

  const DecodedImage({required this.dimensions, this.image, this.rawRgbaBytes});
}

Future<DecodedImage> decodeImageFromPath(
  String imagePath, {
  required bool includeRgbaBytes,
  required bool includeDartUiImage,
}) async {
  final imageData = await File(imagePath).readAsBytes();
  final format = imagePath.split('.').last.toLowerCase();
  final bool skipExifRead =
      Platform.isIOS &&
      format == 'jxl'; // JXL on iOS has issues with EXIF reading
  Map<String, IfdTag> exifData = <String, IfdTag>{};
  if (skipExifRead) {
    _logger.info('Skipping EXIF read for JXL on iOS');
  } else {
    exifData = _normalizeExifResult(await readExifFromBytes(imageData));
  }
  final int orientation =
      exifData['Image Orientation']?.values.firstAsInt() ?? 1;
  if (orientation > 1 && includeRgbaBytes) {
    if (format == 'heic' || format == 'heif') {
      _logger.info(
        "Decoding HEIC/HEIF image with EXIF orientation $orientation",
      );
    } else {
      _logger.warning(
        "Decoding image with EXIF orientation $orientation, for format $format",
      );
    }
  }

  late Image image;
  try {
    image = await decodeImageFromData(imageData);
  } catch (e, s) {
    if (isRawImageExtension(format)) {
      _logger.warning(
        "Skipping JPEG conversion for RAW image format $format because flutter_image_compress is known to crash on unsupported RAW input",
        e,
        s,
      );
      throw Exception(
        'InvalidImageFormatException: Error decoding image of format $format',
      );
    }
    _logger.info(
      'Cannot decode $format on ${Platform.isAndroid ? "Android" : "iOS"}, converting to jpeg',
    );
    try {
      final Uint8List? convertedData =
          await FlutterImageCompress.compressWithFile(
            imagePath,
            format: CompressFormat.jpeg,
            minWidth: 20000, // High value to ensure image is not scaled down
            minHeight: 20000, // High value to ensure image is not scaled down
          );
      image = await decodeImageFromData(convertedData!);
      _logger.info('Conversion successful, jpeg decoded');
      if (image.width >= 20000 || image.height >= 20000) {
        // Failing and storing empty result when the image dimensions are higher than max compression limits
        _logger.severe(
          'Image res too high, W:${image.width} H:${image.height}',
        );
        throw Exception('Res too high W:${image.width} H:${image.height}');
      }
    } catch (e) {
      _logger.severe(
        'Error decoding image of format $format on ${Platform.isAndroid ? "Android" : "iOS"}',
        e,
        s,
      );
      throw Exception(
        'InvalidImageFormatException: Error decoding image of format $format',
      );
    }
  }
  if (!includeRgbaBytes) {
    return DecodedImage(
      dimensions: Dimensions(width: image.width, height: image.height),
      image: includeDartUiImage ? image : null,
    );
  }
  final rawRgbaBytes = await _getRawRgbaBytes(image);
  return DecodedImage(
    dimensions: Dimensions(width: image.width, height: image.height),
    image: includeDartUiImage ? image : null,
    rawRgbaBytes: rawRgbaBytes,
  );
}

Map<String, IfdTag> _normalizeExifResult(dynamic result) {
  if (result is Map<String, IfdTag>) {
    return result;
  }
  final dynamic tags = result.tags;
  if (tags is Map<String, IfdTag>) {
    return tags;
  }
  throw ArgumentError("Unsupported EXIF result type: ${result.runtimeType}");
}

Future<Uint8List?> createSafeJpegDecodeFallbackBytes({
  required String imagePath,
}) async {
  final imageData = await File(imagePath).readAsBytes();
  return createSafeJpegDecodeFallbackBytesFromData(imageData);
}

Uint8List? createSafeJpegDecodeFallbackBytesFromData(Uint8List imageData) {
  try {
    final decoded = img.decodeImage(imageData);
    if (decoded == null) {
      return null;
    }
    final jpeg = img.encodeJpg(decoded, quality: 95);
    return Uint8List.fromList(jpeg);
  } catch (e) {
    final firstLine = e.toString().split('\n').first.trim();
    _logger.warning(
      firstLine.isEmpty
          ? "Safe JPEG conversion failed"
          : "Safe JPEG conversion failed: $firstLine",
    );
    return null;
  }
}

/// Decodes [Uint8List] image data to an ui.[Image] object.
Future<Image> decodeImageFromData(Uint8List imageData) async {
  // Decoding using flutter paint. This is the fastest and easiest method.
  final Image image = await paint.decodeImageFromList(imageData);
  return image;

  // // Similar decoding as above, but without using flutter paint. This is not faster than the above.
  // final Codec codec = await instantiateImageCodecFromBuffer(
  //   await ImmutableBuffer.fromUint8List(imageData),
  // );
  // final FrameInfo frameInfo = await codec.getNextFrame();
  // return frameInfo.image;

  // Decoding using the ImageProvider, same as `image_pixels` package. This is not faster than the above.
  // final Completer<Image> completer = Completer<Image>();
  // final ImageProvider provider = MemoryImage(imageData);
  // final ImageStream stream = provider.resolve(const ImageConfiguration());
  // final ImageStreamListener listener =
  //     ImageStreamListener((ImageInfo info, bool _) {
  //   completer.complete(info.image);
  // });
  // stream.addListener(listener);
  // final Image image = await completer.future;
  // stream.removeListener(listener);
  // return image;
}

Future<Uint8List> _getRawRgbaBytes(Image image) async {
  return await _getByteDataFromImage(image, format: ImageByteFormat.rawRgba);
}

/// Encodes an [Image] object to a [Uint8List], in the png format.
/// Can be used with `Image.memory()`.
Future<Uint8List> _encodeImageToPng(Image image) async {
  return await _getByteDataFromImage(image, format: ImageByteFormat.png);
}

/// Returns the [ByteData] object of the image, in rawRgba format.
///
/// Throws an exception if the image could not be converted to ByteData.
Future<Uint8List> _getByteDataFromImage(
  Image image, {
  required ImageByteFormat format,
}) async {
  final byteData = await image.toByteData(format: format);
  if (byteData == null) {
    _logger.severe('Failed to get byte data in $format from image');
    throw Exception('Failed to get byte data in $format from image');
  }
  return byteData.buffer.asUint8List();
}

/// Generates a face thumbnail from [imageData] and [faceBoxes].
///
/// Returns a [Uint8List] image, in png format.
Future<List<Uint8List>> generateFaceThumbnailsUsingCanvas(
  String imagePath,
  List<FaceBox> faceBoxes,
) async {
  int i = 0; // Index of the faceBox, initialized here for logging purposes
  try {
    final decodedImage = await decodeImageFromPath(
      imagePath,
      includeRgbaBytes: false,
      includeDartUiImage: true,
    );
    final dimensions = decodedImage.dimensions;
    final Image? img = decodedImage.image;
    if (img == null) {
      _logger.severe('Image is null, cannot generate face thumbnails');
      return [];
    }
    final futureFaceThumbnails = <Future<Uint8List>>[];
    for (final faceBox in faceBoxes) {
      // Note that the faceBox values are relative to the image size, so we need to convert them to absolute values first
      final double xMinAbs = faceBox.x * dimensions.width;
      final double yMinAbs = faceBox.y * dimensions.height;
      final double widthAbs = faceBox.width * dimensions.width;
      final double heightAbs = faceBox.height * dimensions.height;

      // Calculate the crop values by adding some padding around the face and making sure it's centered
      const regularPadding = 0.4;
      const minimumPadding = 0.1;
      final num xCrop = (xMinAbs - widthAbs * regularPadding);
      final num xOvershoot = min(0, xCrop).abs() / widthAbs;
      final num widthCrop =
          widthAbs * (1 + 2 * regularPadding) -
          2 * min(xOvershoot, regularPadding - minimumPadding) * widthAbs;
      final num yCrop = (yMinAbs - heightAbs * regularPadding);
      final num yOvershoot = min(0, yCrop).abs() / heightAbs;
      final num heightCrop =
          heightAbs * (1 + 2 * regularPadding) -
          2 * min(yOvershoot, regularPadding - minimumPadding) * heightAbs;

      // Prevent the face from going out of image bounds
      final xCropSafe = xCrop.clamp(0, dimensions.width);
      final yCropSafe = yCrop.clamp(0, dimensions.height);
      final widthCropSafe = widthCrop.clamp(0, dimensions.width - xCropSafe);
      final heightCropSafe = heightCrop.clamp(0, dimensions.height - yCropSafe);

      futureFaceThumbnails.add(
        _cropAndEncodeCanvas(
          img,
          x: xCropSafe.toDouble(),
          y: yCropSafe.toDouble(),
          width: widthCropSafe.toDouble(),
          height: heightCropSafe.toDouble(),
        ),
      );
      i++;
    }
    final List<Uint8List> faceThumbnails = await Future.wait(
      futureFaceThumbnails,
    );
    return faceThumbnails;
  } catch (e, s) {
    _logger.severe(
      'Error generating face thumbnails. cropImage problematic input argument: ${i}th facebox: ${faceBoxes[i].toString()}',
      e,
      s,
    );
    return [];
  }
}

Future<(Float32List, Dimensions)> preprocessImageYoloFace(
  Dimensions dim,
  Uint8List rawRgbaBytes,
) async {
  const requiredWidth = 640;
  const requiredHeight = 640;
  final scale = min(requiredWidth / dim.width, requiredHeight / dim.height);
  final scaledWidth = (dim.width * scale).round().clamp(0, requiredWidth);
  final scaledHeight = (dim.height * scale).round().clamp(0, requiredHeight);

  final processedBytes = Float32List(3 * requiredHeight * requiredWidth);

  final buffer = Float32List.view(processedBytes.buffer);
  int pixelIndex = 0;
  const int channelOffsetGreen = requiredHeight * requiredWidth;
  const int channelOffsetBlue = 2 * requiredHeight * requiredWidth;
  for (var h = 0; h < requiredHeight; h++) {
    for (var w = 0; w < requiredWidth; w++) {
      late RGB pixel;
      if (w >= scaledWidth || h >= scaledHeight) {
        pixel = const (114, 114, 114);
      } else {
        pixel = _getPixelBilinear(w / scale, h / scale, dim, rawRgbaBytes);
      }
      buffer[pixelIndex] = pixel.$1 / 255;
      buffer[pixelIndex + channelOffsetGreen] = pixel.$2 / 255;
      buffer[pixelIndex + channelOffsetBlue] = pixel.$3 / 255;
      pixelIndex++;
    }
  }

  return (processedBytes, Dimensions(width: scaledWidth, height: scaledHeight));
}

Future<Float32List> preprocessImageClip(
  Dimensions dim,
  Uint8List rawRgbaBytes,
) async {
  const int requiredWidth = 256;
  const int requiredHeight = 256;
  const int requiredSize = 3 * requiredWidth * requiredHeight;
  final scale = max(requiredWidth / dim.width, requiredHeight / dim.height);
  final bool useAntiAlias = scale < 0.8;
  final scaledWidth = (dim.width * scale).round();
  final scaledHeight = (dim.height * scale).round();
  final widthOffset = max(0, scaledWidth - requiredWidth) / 2;
  final heightOffset = max(0, scaledHeight - requiredHeight) / 2;

  final processedBytes = Float32List(requiredSize);
  final buffer = Float32List.view(processedBytes.buffer);
  int pixelIndex = 0;
  const int greenOff = requiredHeight * requiredWidth;
  const int blueOff = 2 * requiredHeight * requiredWidth;
  for (var h = 0 + heightOffset; h < scaledHeight - heightOffset; h++) {
    for (var w = 0 + widthOffset; w < scaledWidth - widthOffset; w++) {
      final RGB pixel = _getPixelBilinear(
        w / scale,
        h / scale,
        dim,
        rawRgbaBytes,
        antiAlias: useAntiAlias,
      );
      buffer[pixelIndex] = pixel.$1 / 255;
      buffer[pixelIndex + greenOff] = pixel.$2 / 255;
      buffer[pixelIndex + blueOff] = pixel.$3 / 255;
      pixelIndex++;
    }
  }

  return processedBytes;
}

Future<(Float32List, List<AlignmentResult>, List<bool>, List<double>, Size)>
preprocessToMobileFaceNetFloat32List(
  Dimensions dim,
  Uint8List rawRgbaBytes,
  List<FaceDetectionRelative> relativeFaces, {
  int width = 112,
  int height = 112,
}) async {
  final Size originalSize = Size(dim.width.toDouble(), dim.height.toDouble());

  final List<FaceDetectionAbsolute> absoluteFaces =
      relativeToAbsoluteDetections(
        relativeDetections: relativeFaces,
        imageWidth: dim.width,
        imageHeight: dim.height,
      );

  final alignedImagesFloat32List = Float32List(
    3 * width * height * absoluteFaces.length,
  );
  final alignmentResults = <AlignmentResult>[];
  final isBlurs = <bool>[];
  final blurValues = <double>[];

  int alignedImageIndex = 0;
  for (final face in absoluteFaces) {
    final (alignmentResult, correctlyEstimated) = SimilarityTransform.estimate(
      face.allKeypoints,
    );
    if (!correctlyEstimated) {
      _logger.severe(
        'Face alignment failed because not able to estimate SimilarityTransform, for face: $face',
      );
      throw Exception(
        'Face alignment failed because not able to estimate SimilarityTransform',
      );
    }
    alignmentResults.add(alignmentResult);

    _warpAffineFloat32List(
      dim,
      rawRgbaBytes,
      alignmentResult.affineMatrix,
      alignedImagesFloat32List,
      alignedImageIndex,
    );

    final faceGrayMatrix = _createGrayscaleIntMatrixFromNormalized2List(
      alignedImagesFloat32List,
      alignedImageIndex,
    );

    alignedImageIndex += 3 * width * height;
    final (
      isBlur,
      blurValue,
    ) = await BlurDetectionService.predictIsBlurGrayLaplacian(
      faceGrayMatrix,
      faceDirection: face.getFaceDirection(),
    );
    isBlurs.add(isBlur);
    blurValues.add(blurValue);
  }
  return (
    alignedImagesFloat32List,
    alignmentResults,
    isBlurs,
    blurValues,
    originalSize,
  );
}

/// Reads the pixel color at the specified coordinates.
RGB _readPixelColor(int x, int y, Dimensions dim, Uint8List rgbaBytes) {
  if (y < 0 || y >= dim.height || x < 0 || x >= dim.width) {
    if (y < -maxKernelRadius ||
        y >= dim.height + maxKernelRadius ||
        x < -maxKernelRadius ||
        x >= dim.width + maxKernelRadius) {
      _logger.severe(
        '`readPixelColor`: Invalid pixel coordinates, out of bounds. x: $x, y: $y',
      );
    }
    return const (114, 114, 114);
  }

  assert(rgbaBytes.lengthInBytes == 4 * dim.width * dim.height);

  final int byteOffset = 4 * (dim.width * y + x);
  return (
    rgbaBytes[byteOffset], // red
    rgbaBytes[byteOffset + 1], // green
    rgbaBytes[byteOffset + 2], // blue
  );
}

RGB _getPixelBlurred(int x, int y, Dimensions dim, Uint8List rgbaBytes) {
  double r = 0, g = 0, b = 0;
  for (int ky = 0; ky < gaussianKernelSize; ky++) {
    for (int kx = 0; kx < gaussianKernelSize; kx++) {
      final int px = (x - gaussianKernelRadius + kx);
      final int py = (y - gaussianKernelRadius + ky);

      final RGB pixelRgbTuple = _readPixelColor(px, py, dim, rgbaBytes);
      final double weight = gaussianKernel[ky][kx];

      r += pixelRgbTuple.$1 * weight;
      g += pixelRgbTuple.$2 * weight;
      b += pixelRgbTuple.$3 * weight;
    }
  }
  return (r.round(), g.round(), b.round());
}

List<List<int>> _createGrayscaleIntMatrixFromNormalized2List(
  Float32List imageList,
  int startIndex, {
  int width = 112,
  int height = 112,
}) {
  return List.generate(
    height,
    (y) => List.generate(width, (x) {
      // 0.299 ∙ Red + 0.587 ∙ Green + 0.114 ∙ Blue
      final pixelIndex = startIndex + 3 * (y * width + x);
      return (0.299 * ((imageList[pixelIndex] + 1) * 127.5) +
              0.587 * ((imageList[pixelIndex + 1] + 1) * 127.5) +
              0.114 * ((imageList[pixelIndex + 2] + 1) * 127.5))
          .round()
          .clamp(0, 255);
    }),
  );
}

Future<Image> _cropImage(
  Image image, {
  required double x,
  required double y,
  required double width,
  required double height,
}) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromPoints(const Offset(0, 0), Offset(width, height)),
  );

  canvas.drawImageRect(
    image,
    Rect.fromPoints(Offset(x, y), Offset(x + width, y + height)),
    Rect.fromPoints(const Offset(0, 0), Offset(width, height)),
    Paint()..filterQuality = FilterQuality.medium,
  );

  final picture = recorder.endRecording();
  return picture.toImage(width.toInt(), height.toInt());
}

void _warpAffineFloat32List(
  Dimensions dim,
  Uint8List rawRgbaBytes,
  List<List<double>> affineMatrix,
  Float32List outputList,
  int startIndex, {
  int width = 112,
  int height = 112,
}) {
  if (width != 112 || height != 112) {
    throw Exception(
      'Width and height must be 112, other transformations are not supported yet.',
    );
  }

  final transformationMatrix = affineMatrix
      .map(
        (row) => row.map((e) {
          if (e != 1.0) {
            return e * 112;
          } else {
            return 1.0;
          }
        }).toList(),
      )
      .toList();

  final A = Matrix.fromList([
    [transformationMatrix[0][0], transformationMatrix[0][1]],
    [transformationMatrix[1][0], transformationMatrix[1][1]],
  ]);
  final aInverse = A.inverse();
  // final aInverseMinus = aInverse * -1;
  final B = Vector.fromList([
    transformationMatrix[0][2],
    transformationMatrix[1][2],
  ]);
  final b00 = B[0];
  final b10 = B[1];
  final a00Prime = aInverse[0][0];
  final a01Prime = aInverse[0][1];
  final a10Prime = aInverse[1][0];
  final a11Prime = aInverse[1][1];

  for (int yTrans = 0; yTrans < height; ++yTrans) {
    for (int xTrans = 0; xTrans < width; ++xTrans) {
      // Perform inverse affine transformation (original implementation, intuitive but slow)
      // final X = aInverse * (Vector.fromList([xTrans, yTrans]) - B);
      // final X = aInverseMinus * (B - [xTrans, yTrans]);
      // final xList = X.asFlattenedList;
      // num xOrigin = xList[0];
      // num yOrigin = xList[1];

      // Perform inverse affine transformation (fast implementation, less intuitive)
      final num xOrigin = (xTrans - b00) * a00Prime + (yTrans - b10) * a01Prime;
      final num yOrigin = (xTrans - b00) * a10Prime + (yTrans - b10) * a11Prime;

      final RGB pixel = _getPixelBicubic(xOrigin, yOrigin, dim, rawRgbaBytes);

      // Set the new pixel
      outputList[startIndex + 3 * (yTrans * width + xTrans)] =
          (pixel.$1 / 127.5) - 1;
      outputList[startIndex + 3 * (yTrans * width + xTrans) + 1] =
          (pixel.$2 / 127.5) - 1;
      outputList[startIndex + 3 * (yTrans * width + xTrans) + 2] =
          (pixel.$3 / 127.5) - 1;
    }
  }
}

Future<Uint8List> _cropAndEncodeCanvas(
  Image image, {
  required double x,
  required double y,
  required double width,
  required double height,
}) async {
  final croppedImage = await _cropImage(
    image,
    x: x,
    y: y,
    width: width,
    height: height,
  );
  return await _encodeImageToPng(croppedImage);
}

Future<List<Uint8List>> compressFaceThumbnails(Map args) async {
  final listPngBytes = args['listPngBytes'] as List<Uint8List>;
  final List<Future<Uint8List>> compressedBytesList = [];
  try {
    for (final pngBytes in listPngBytes) {
      final compressedBytes = FlutterImageCompress.compressWithList(
        pngBytes,
        quality: _faceThumbnailCompressionQuality,
        format: CompressFormat.jpeg,
        minWidth: _faceThumbnailMinDimension,
        minHeight: _faceThumbnailMinDimension,
      );
      compressedBytesList.add(compressedBytes);
    }
    return await Future.wait(compressedBytesList);
  } catch (e, s) {
    _logger.warning(
      'Failed to compress face thumbnail, using original. Size: ${listPngBytes.map((e) => e.length).toList()} bytes',
      e,
      s,
    );
    rethrow;
  }
}

RGB _getPixelBilinear(
  num fx,
  num fy,
  Dimensions dim,
  Uint8List rawRgbaBytes, {
  bool antiAlias = false,
}) {
  // Clamp to image boundaries
  fx = fx.clamp(0, dim.width - 1);
  fy = fy.clamp(0, dim.height - 1);

  // Get the surrounding coordinates and their weights
  final int x0 = fx.floor();
  final int x1 = fx.ceil();
  final int y0 = fy.floor();
  final int y1 = fy.ceil();
  final dx = fx - x0;
  final dy = fy - y0;
  final dx1 = 1.0 - dx;
  final dy1 = 1.0 - dy;

  // Get the original pixels (with gaussian blur if antialias)
  final RGB Function(int, int, Dimensions, Uint8List) readPixel = antiAlias
      ? _getPixelBlurred
      : _readPixelColor;
  final RGB pixel1 = readPixel(x0, y0, dim, rawRgbaBytes);
  final RGB pixel2 = readPixel(x1, y0, dim, rawRgbaBytes);
  final RGB pixel3 = readPixel(x0, y1, dim, rawRgbaBytes);
  final RGB pixel4 = readPixel(x1, y1, dim, rawRgbaBytes);

  int bilinear(num val1, num val2, num val3, num val4) =>
      (val1 * dx1 * dy1 + val2 * dx * dy1 + val3 * dx1 * dy + val4 * dx * dy)
          .round();

  // Calculate the weighted sum of pixels
  final int r = bilinear(pixel1.$1, pixel2.$1, pixel3.$1, pixel4.$1);
  final int g = bilinear(pixel1.$2, pixel2.$2, pixel3.$2, pixel4.$2);
  final int b = bilinear(pixel1.$3, pixel2.$3, pixel3.$3, pixel4.$3);

  return (r, g, b);
}

/// Get the pixel value using Bicubic Interpolation. Code taken mainly from https://github.com/brendan-duncan/image/blob/6e407612752ffdb90b28cd5863c7f65856349348/lib/src/image/image.dart#L697
RGB _getPixelBicubic(num fx, num fy, Dimensions dim, Uint8List rawRgbaBytes) {
  fx = fx.clamp(0, dim.width - 1);
  fy = fy.clamp(0, dim.height - 1);

  final x = fx.toInt() - (fx >= 0.0 ? 0 : 1);
  final px = x - 1;
  final nx = x + 1;
  final ax = x + 2;
  final y = fy.toInt() - (fy >= 0.0 ? 0 : 1);
  final py = y - 1;
  final ny = y + 1;
  final ay = y + 2;
  final dx = fx - x;
  final dy = fy - y;
  num cubic(num dx, num ipp, num icp, num inp, num iap) =>
      icp +
      0.5 *
          (dx * (-ipp + inp) +
              dx * dx * (2 * ipp - 5 * icp + 4 * inp - iap) +
              dx * dx * dx * (-ipp + 3 * icp - 3 * inp + iap));

  final icc = _readPixelColor(x, y, dim, rawRgbaBytes);

  final ipp = px < 0 || py < 0
      ? icc
      : _readPixelColor(px, py, dim, rawRgbaBytes);
  final icp = px < 0 ? icc : _readPixelColor(x, py, dim, rawRgbaBytes);
  final inp = py < 0 || nx >= dim.width
      ? icc
      : _readPixelColor(nx, py, dim, rawRgbaBytes);
  final iap = ax >= dim.width || py < 0
      ? icc
      : _readPixelColor(ax, py, dim, rawRgbaBytes);

  final ip0 = cubic(dx, ipp.$1, icp.$1, inp.$1, iap.$1);
  final ip1 = cubic(dx, ipp.$2, icp.$2, inp.$2, iap.$2);
  final ip2 = cubic(dx, ipp.$3, icp.$3, inp.$3, iap.$3);
  // final ip3 = cubic(dx, ipp.a, icp.a, inp.a, iap.a);

  final ipc = px < 0 ? icc : _readPixelColor(px, y, dim, rawRgbaBytes);
  final inc = nx >= dim.width ? icc : _readPixelColor(nx, y, dim, rawRgbaBytes);
  final iac = ax >= dim.width ? icc : _readPixelColor(ax, y, dim, rawRgbaBytes);

  final ic0 = cubic(dx, ipc.$1, icc.$1, inc.$1, iac.$1);
  final ic1 = cubic(dx, ipc.$2, icc.$2, inc.$2, iac.$2);
  final ic2 = cubic(dx, ipc.$3, icc.$3, inc.$3, iac.$3);
  // final ic3 = cubic(dx, ipc.a, icc.a, inc.a, iac.a);

  final ipn = px < 0 || ny >= dim.height
      ? icc
      : _readPixelColor(px, ny, dim, rawRgbaBytes);
  final icn = ny >= dim.height
      ? icc
      : _readPixelColor(x, ny, dim, rawRgbaBytes);
  final inn = nx >= dim.width || ny >= dim.height
      ? icc
      : _readPixelColor(nx, ny, dim, rawRgbaBytes);
  final ian = ax >= dim.width || ny >= dim.height
      ? icc
      : _readPixelColor(ax, ny, dim, rawRgbaBytes);

  final in0 = cubic(dx, ipn.$1, icn.$1, inn.$1, ian.$1);
  final in1 = cubic(dx, ipn.$2, icn.$2, inn.$2, ian.$2);
  final in2 = cubic(dx, ipn.$3, icn.$3, inn.$3, ian.$3);
  // final in3 = cubic(dx, ipn.a, icn.a, inn.a, ian.a);

  final ipa = px < 0 || ay >= dim.height
      ? icc
      : _readPixelColor(px, ay, dim, rawRgbaBytes);
  final ica = ay >= dim.height
      ? icc
      : _readPixelColor(x, ay, dim, rawRgbaBytes);
  final ina = nx >= dim.width || ay >= dim.height
      ? icc
      : _readPixelColor(nx, ay, dim, rawRgbaBytes);
  final iaa = ax >= dim.width || ay >= dim.height
      ? icc
      : _readPixelColor(ax, ay, dim, rawRgbaBytes);

  final ia0 = cubic(dx, ipa.$1, ica.$1, ina.$1, iaa.$1);
  final ia1 = cubic(dx, ipa.$2, ica.$2, ina.$2, iaa.$2);
  final ia2 = cubic(dx, ipa.$3, ica.$3, ina.$3, iaa.$3);
  // final ia3 = cubic(dx, ipa.a, ica.a, ina.a, iaa.a);

  final c0 = cubic(dy, ip0, ic0, in0, ia0).clamp(0, 255).toInt();
  final c1 = cubic(dy, ip1, ic1, in1, ia1).clamp(0, 255).toInt();
  final c2 = cubic(dy, ip2, ic2, in2, ia2).clamp(0, 255).toInt();
  // final c3 = cubic(dy, ip3, ic3, in3, ia3);

  return (c0, c1, c2); // (red, green, blue)
}

List<List<double>> create2DGaussianKernel(int size, double sigma) {
  final List<List<double>> kernel = List.generate(
    size,
    (_) => List<double>.filled(size, 0),
  );
  double sum = 0.0;
  final int center = size ~/ 2;

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final int dx = x - center;
      final int dy = y - center;
      final double g =
          (1 / (2 * pi * sigma * sigma)) *
          exp(-(dx * dx + dy * dy) / (2 * sigma * sigma));
      kernel[y][x] = g;
      sum += g;
    }
  }

  // Normalize the kernel
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      kernel[y][x] /= sum;
    }
  }

  return kernel;
}
