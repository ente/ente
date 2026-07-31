import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:exif_reader/exif_reader.dart' as exif;
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
// ignore: implementation_imports
import 'package:image/src/util/rational.dart' as img_util;
import 'package:logging/logging.dart';
import "package:photos/models/file/file.dart";
import "package:photos/module/metadata/exif.dart" show getExif;

final _logger = Logger("ImageUtil");

const Set<String> _rawImageExtensions = {
  'arw', // Sony
  'cr2', 'cr3', // Canon
  'nef', 'nrw', // Nikon
  'dng', // Adobe/generic
  'orf', // Olympus
  'raf', // Fuji
  'rw2', // Panasonic
  'pef', // Pentax
  'srw', // Samsung
  '3fr', 'fff', // Hasselblad
  'rwl', // Leica
  'x3f', // Sigma
  'iiq', // Phase One
  'kdc', 'dcr', // Kodak
  'mrw', // Minolta
  'erf', // Epson
  'mef', // Mamiya
  'raw', // Generic
};

bool isRawImageExtension(String extension) =>
    _rawImageExtensions.contains(extension.toLowerCase());

Future<ImageInfo> getImageInfo(ImageProvider imageProvider) {
  final completer = Completer<ImageInfo>();
  final imageStream = imageProvider.resolve(const ImageConfiguration());
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (imageInfo, _) {
      if (completer.isCompleted) return;
      imageStream.removeListener(listener);
      completer.complete(imageInfo);
    },
    onError: (error, stackTrace) {
      if (completer.isCompleted) return;
      imageStream.removeListener(listener);
      completer.completeError(error, stackTrace ?? StackTrace.current);
    },
  );
  imageStream.addListener(listener);
  return completer.future;
}

// dart format off
const _copiedExifFields = [
  (ifd: "Image", src: "Make",                    dst: "Make",                    render: false),
  (ifd: "Image", src: "Model",                   dst: "Model",                   render: false),
  (ifd: "Image", src: "Orientation",             dst: "Orientation",             render: true),
  (ifd: "Image", src: "Artist",                  dst: "Artist",                  render: false),
  (ifd: "Image", src: "Copyright",               dst: "Copyright",               render: false),
  (ifd: "EXIF",  src: "DateTimeOriginal",        dst: "DateTimeOriginal",        render: false),
  (ifd: "EXIF",  src: "DateTimeDigitized",       dst: "DateTimeDigitized",       render: false),
  (ifd: "EXIF",  src: "OffsetTimeOriginal",      dst: "OffsetTimeOriginal",      render: false),
  (ifd: "EXIF",  src: "LensModel",               dst: "LensModel",               render: false),
  (ifd: "EXIF",  src: "ExposureTime",            dst: "ExposureTime",            render: false),
  (ifd: "EXIF",  src: "FNumber",                 dst: "FNumber",                 render: false),
  (ifd: "EXIF",  src: "ISOSpeedRatings",         dst: "ISOSpeed",                render: false),
  (ifd: "EXIF",  src: "FocalLength",             dst: "FocalLength",             render: false),
  (ifd: "EXIF",  src: "FocalLengthIn35mmFilm",   dst: "FocalLengthIn35mmFilm",   render: false),
  (ifd: "EXIF",  src: "ColorSpace",              dst: "ColorSpace",              render: true),
  (ifd: "GPS",   src: "GPSLatitudeRef",          dst: "GPSLatitudeRef",          render: false),
  (ifd: "GPS",   src: "GPSLatitude",             dst: "GPSLatitude",             render: false),
  (ifd: "GPS",   src: "GPSLongitudeRef",         dst: "GPSLongitudeRef",         render: false),
  (ifd: "GPS",   src: "GPSLongitude",            dst: "GPSLongitude",            render: false),
  (ifd: "GPS",   src: "GPSAltitudeRef",          dst: "GPSAltitudeRef",          render: false),
  (ifd: "GPS",   src: "GPSAltitude",             dst: "GPSAltitude",             render: false),
  (ifd: "GPS",   src: "GPSMapDatum",             dst: "GPSMapDatum",             render: false),
];
// dart format on

img.IfdValue? _convertExifReaderValueToImageValue(exif.IfdTag? tag) {
  final values = tag?.values;
  if (tag == null || values == null || values is exif.IfdNone) return null;

  List<int> ints() => values.toList().cast<int>();
  List<double> doubles() =>
      values.toList().map((value) => (value as num).toDouble()).toList();
  List<img_util.Rational> ratios() => values
      .toList()
      .cast<exif.Ratio>()
      .map((value) => img_util.Rational(value.numerator, value.denominator))
      .toList();

  return switch (tag.tagType) {
    "Byte" => img.IfdByteValue.list(Uint8List.fromList(ints())),
    "ASCII" => img.IfdValueAscii(
      String.fromCharCodes(ints().takeWhile((byte) => byte != 0)),
    ),
    "Short" => img.IfdValueShort.list(ints()),
    "Long" || "IFD" => img.IfdValueLong.list(ints()),
    "Signed Byte" => img.IfdValueSByte.list(ints()),
    "Undefined" => img.IfdValueUndefined.list(ints()),
    "Signed Short" => img.IfdValueSShort.list(ints()),
    "Signed Long" => img.IfdValueSLong.list(ints()),
    "Ratio" => img.IfdValueRational.list(ratios()),
    "Signed Ratio" => img.IfdValueSRational.list(ratios()),
    "Single-Precision Floating Point (32-bit)" => img.IfdValueSingle.list(
      doubles(),
    ),
    "Double-Precision Floating Point (64-bit)" => img.IfdValueDouble.list(
      doubles(),
    ),
    _ => null,
  };
}

// TODO: Move EXIF writes off the Dart image library to a Rust implementation.
Future<void> copyEXIF(
  EnteFile src,
  img.Image dest, {
  bool copyRenderingFields = true,
}) async {
  final srcExif = await getExif(src);
  for (final field in _copiedExifFields) {
    if (!copyRenderingFields && field.render) continue;
    final destIfd = switch (field.ifd) {
      "Image" => dest.exif.imageIfd,
      "EXIF" => dest.exif.exifIfd,
      "GPS" => dest.exif.gpsIfd,
      _ => throw UnsupportedError("Unknown EXIF IFD: ${field.ifd}"),
    };
    final value = _convertExifReaderValueToImageValue(
      srcExif["${field.ifd} ${field.src}"],
    );
    if (value != null) destIfd[field.dst] = value;
  }
}

Future<({int width, int height})?> getImageDimensions({
  String? imagePath,
  Uint8List? imageBytes,
}) async {
  if (imagePath == null && imageBytes == null) {
    throw ArgumentError("imagePath and imageBytes cannot be null");
  }
  try {
    late Uint8List bytes;
    if (imagePath != null) {
      bytes = await File(imagePath).readAsBytes();
    } else {
      bytes = imageBytes!;
    }
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frameInfo = await codec.getNextFrame();
      try {
        if (frameInfo.image.width == 0 || frameInfo.image.height == 0) {
          return null;
        }
        return (width: frameInfo.image.width, height: frameInfo.image.height);
      } finally {
        frameInfo.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } catch (e) {
    _logger.severe("Failed to get image size", e);
    return null;
  }
}
