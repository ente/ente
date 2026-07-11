import "dart:async";
import "dart:io";
import 'dart:typed_data';

import "package:computer/computer.dart";
import 'package:exif_reader/exif_reader.dart';
import 'package:image/image.dart' as img;
// ignore: implementation_imports
import 'package:image/src/util/rational.dart' as img_util;
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:photos/models/file/file.dart';
import "package:photos/models/file/file_type.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/metadata/file_magic.dart";
import 'package:photos/module/download/file.dart';
import "package:photos/services/location_service.dart";
import 'package:random_access_source/random_access_source.dart';

const kDateTimeOriginal = "EXIF DateTimeOriginal";
const _imageDateTime = "Image DateTime";
const _exifOffsetKeys = [
  "EXIF OffsetTime",
  "EXIF OffsetTimeOriginal",
  "EXIF OffsetTimeDigitized",
];
const _exifDateTimePattern = "yyyy:MM:dd HH:mm:ss";
const _emptyExifDateTime = "0000:00:00 00:00:00";

final _logger = Logger("ExifUtil");

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
  (ifd: "GPS",   src: "GPSAltitudeRef",           dst: "GPSAltitudeRef",          render: false),
  (ifd: "GPS",   src: "GPSAltitude",              dst: "GPSAltitude",             render: false),
  (ifd: "GPS",   src: "GPSMapDatum",              dst: "GPSMapDatum",             render: false),
];
// dart format on

img.IfdValue? _imageExifValue(IfdTag? tag) {
  final values = tag?.values;
  if (tag == null || values == null || values is IfdNone) {
    return null;
  }

  List<int> ints() => values.toList().cast<int>();
  List<double> doubles() =>
      values.toList().map((value) => (value as num).toDouble()).toList();
  List<img_util.Rational> ratios() => values
      .toList()
      .cast<Ratio>()
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
Future<void> copyExif(
  EnteFile source,
  img.Image destination, {
  bool copyRenderingFields = true,
}) async {
  final sourceExif = await getExif(source);
  for (final field in _copiedExifFields) {
    if (!copyRenderingFields && field.render) {
      continue;
    }
    final destinationIfd = switch (field.ifd) {
      "Image" => destination.exif.imageIfd,
      "EXIF" => destination.exif.exifIfd,
      "GPS" => destination.exif.gpsIfd,
      _ => throw UnsupportedError("Unknown EXIF IFD: ${field.ifd}"),
    };
    final value = _imageExifValue(sourceExif["${field.ifd} ${field.src}"]);
    if (value != null) {
      destinationIfd[field.dst] = value;
    }
  }
}

final _standardExifDateTimePattern = RegExp(
  r'^(\d{4}:(0[1-9]|1[0-2]):(0[1-9]|[12]\d|3[01]) ([01]\d|2[0-3]):([0-5]\d):([0-5]\d))([\.:]\d+)?$',
);
final _isoExifDateTimePattern = RegExp(
  r'^(\d{4})-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])[T ]([01]\d|2[0-3]):([0-5]\d):([0-5]\d)([\.:]\d+)?([Zz]|[+-](?:[01]\d|2[0-3]):?[0-5]\d)?$',
);
final _offsetPattern = RegExp(r'^([Zz]|[+-](?:[01]\d|2[0-3]):?[0-5]\d)$');

bool shouldReadExif(EnteFile file) {
  return file.fileType == FileType.image || file.fileType == FileType.livePhoto;
}

Future<Map<String, IfdTag>> getExif(EnteFile file) async {
  try {
    if (!shouldReadExif(file)) {
      return <String, IfdTag>{};
    }
    final File? originFile = await getFile(file, isOrigin: true);
    if (originFile == null) {
      throw Exception("Failed to fetch origin file");
    }
    final exif = await readExifAsync(originFile);
    if (!file.isRemoteOnlyFile && Platform.isIOS) {
      await originFile.delete();
    }
    return exif;
  } catch (e) {
    _logger.severe("failed to getExif", e);
    rethrow;
  }
}

Future<Map<String, IfdTag>?> tryExifFromFile(File originFile) async {
  try {
    final exif = await readExifAsync(originFile);
    return exif;
  } catch (e, s) {
    _logger.severe("failed to get exif from origin file", e, s);
    return null;
  }
}

String? extractPrintableExifValue(IfdTag? tag) {
  final printable = tag?.printable.trim();
  if (printable == null || printable.isEmpty) {
    return null;
  }
  if (printable.toLowerCase() == 'null') {
    return null;
  }
  return printable;
}

bool shouldSwapDimensionsForExifOrientation(Map<String, IfdTag>? exifData) {
  final orientation = exifData?['Image Orientation']?.values.firstAsInt() ?? 1;
  // EXIF orientations 5-8 are rotated 90/270 variants and require w/h swap.
  return orientation >= 5 && orientation <= 8;
}

class ParsedExifDateTime {
  ParsedExifDateTime(this.time, String? dateTime, this.offsetTime)
    : dateTime = dateTime != null && dateTime.endsWith('Z')
          ? dateTime.substring(0, dateTime.length - 1)
          : dateTime;

  final DateTime time;
  final String? dateTime;
  final String? offsetTime;

  @override
  String toString() {
    return "ParsedExifDateTime{time: $time, dateTime: $dateTime, offsetTime: $offsetTime}";
  }
}

Future<ParsedExifDateTime?> tryParseExifDateTime(
  File? file,
  Map<String, IfdTag>? exifData,
) async {
  try {
    assert(file != null || exifData != null);
    final exif = exifData ?? await readExifAsync(file!);
    final exifTime =
        exif[kDateTimeOriginal]?.printable ?? exif[_imageDateTime]?.printable;
    if (exifTime == null || exifTime == _emptyExifDateTime) {
      return null;
    }
    String? exifOffsetTime;
    for (final key in _exifOffsetKeys) {
      final offset = exif[key];
      if (offset != null) {
        exifOffsetTime = offset.printable;
        break;
      }
    }
    try {
      return getDateTimeInDeviceTimezone(exifTime, exifOffsetTime);
    } on FormatException {
      _logger.warning("Ignoring invalid EXIF date time: $exifTime");
    }
  } catch (e, s) {
    _logger.severe("failed to getCreationTimeFromEXIF", e, s);
  }
  return null;
}

ParsedExifDateTime getDateTimeInDeviceTimezone(
  String exifTime,
  String? offsetString,
) {
  final trimmedExifTime = exifTime.trim();
  if (_isoExifDateTimePattern.hasMatch(trimmedExifTime)) {
    return _getIsoExifDateTimeInDeviceTimezone(trimmedExifTime, offsetString);
  }
  if (_standardExifDateTimePattern.hasMatch(trimmedExifTime)) {
    return _getStandardExifDateTimeInDeviceTimezone(
      trimmedExifTime,
      offsetString,
    );
  }
  throw FormatException("Unsupported EXIF date time format", exifTime);
}

ParsedExifDateTime _getStandardExifDateTimeInDeviceTimezone(
  String exifTime,
  String? offsetString,
) {
  final offsetTime = _normalizeOffset(offsetString);
  final hasOffset = offsetTime != null;
  final match = _standardExifDateTimePattern.firstMatch(exifTime)!;
  final DateTime result = DateFormat(_exifDateTimePattern)
      .parseStrict(match.group(1)!, hasOffset)
      .add(
        Duration(microseconds: _parseFractionalMicroseconds(match.group(7))),
      );
  if (hasOffset && offsetTime != "Z") {
    final List<String> splitHHMM = offsetTime.split(":");
    final int offsetHours = int.parse(splitHHMM[0]);
    final int offsetMinutes =
        int.parse(splitHHMM[1]) * (offsetHours.isNegative ? -1 : 1);
    // Adjust the date for the offset to get the photo's correct UTC time
    final photoUtcDate = result.add(
      Duration(hours: -offsetHours, minutes: -offsetMinutes),
    );
    // Convert the UTC time to the device's local time
    final deviceLocalTime = photoUtcDate.toLocal();
    return ParsedExifDateTime(
      deviceLocalTime,
      formatPubMagicDateTime(result),
      offsetTime,
    );
  }
  return ParsedExifDateTime(
    result,
    formatPubMagicDateTime(result),
    offsetTime == "Z" ? "Z" : null,
  );
}

ParsedExifDateTime _getIsoExifDateTimeInDeviceTimezone(
  String exifTime,
  String? offsetString,
) {
  final match = _isoExifDateTimePattern.firstMatch(exifTime.trim());
  if (match == null) {
    throw FormatException("Unsupported EXIF date time format", exifTime);
  }

  final metadataDateTime = _parseIsoDateTimeComponents(match);
  final localDateTimeString = formatPubMagicDateTime(metadataDateTime);
  final offsetTime =
      _normalizeOffset(match.group(8)) ?? _normalizeOffset(offsetString);

  if (offsetTime != null) {
    final deviceLocalTime = DateTime.parse(
      "$localDateTimeString$offsetTime",
    ).toLocal();
    return ParsedExifDateTime(
      deviceLocalTime,
      formatPubMagicDateTime(metadataDateTime),
      offsetTime,
    );
  }

  return ParsedExifDateTime(
    DateTime(
      metadataDateTime.year,
      metadataDateTime.month,
      metadataDateTime.day,
      metadataDateTime.hour,
      metadataDateTime.minute,
      metadataDateTime.second,
      metadataDateTime.millisecond,
      metadataDateTime.microsecond,
    ),
    formatPubMagicDateTime(metadataDateTime),
    null,
  );
}

String? _normalizeOffset(String? offsetString) {
  final offset = offsetString?.trim();
  if (offset == null || offset.isEmpty) {
    return null;
  }
  if (!_offsetPattern.hasMatch(offset)) {
    return null;
  }
  final normalizedOffset = offset.toUpperCase();
  if (normalizedOffset == "Z" || normalizedOffset.length == 6) {
    return normalizedOffset;
  }
  return "${normalizedOffset.substring(0, 3)}:${normalizedOffset.substring(3)}";
}

DateTime _parseIsoDateTimeComponents(RegExpMatch match) {
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final microsecond = _parseFractionalMicroseconds(match.group(7));
  final dateTime = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    microsecond ~/ Duration.microsecondsPerMillisecond,
    microsecond % Duration.microsecondsPerMillisecond,
  );
  if (dateTime.year != year ||
      dateTime.month != month ||
      dateTime.day != day ||
      dateTime.hour != hour ||
      dateTime.minute != minute ||
      dateTime.second != second) {
    throw FormatException("Invalid EXIF date time", match.group(0));
  }
  return dateTime;
}

int _parseFractionalMicroseconds(String? fraction) {
  if (fraction == null) {
    return 0;
  }
  final paddedFraction = fraction.substring(1).padRight(6, "0");
  return int.parse(paddedFraction.substring(0, 6));
}

Location? locationFromExif(Map<String, IfdTag> exif) {
  try {
    return gpsDataFromExif(exif).toLocationObj();
  } catch (e, s) {
    _logger.severe("failed to get location from exif", e, s);
    return null;
  }
}

Future<Map<String, IfdTag>> _readExifArgs(Map<String, dynamic> args) {
  final file = args["file"] as File;
  return FileRASource.loadFile(file).then((src) async {
    try {
      return _normalizeExifResult(await readExifFromSource(src));
    } finally {
      await src.close();
    }
  });
}

Future<Map<String, IfdTag>> readExifAsync(File file) {
  return Computer.shared().compute(
    _readExifArgs,
    param: {"file": file},
    taskName: "readExifAsync",
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

GPSData gpsDataFromExif(Map<String, IfdTag> exif) {
  final latitude = exif["GPS GPSLatitude"];
  final longitude = exif["GPS GPSLongitude"];
  return GPSData(
    exif["GPS GPSLatitudeRef"]?.toString(),
    latitude == null ? null : _gpsCoordinateParts(latitude),
    exif["GPS GPSLongitudeRef"]?.toString(),
    longitude == null ? null : _gpsCoordinateParts(longitude),
  );
}

List<double> _gpsCoordinateParts(IfdTag tag) {
  return tag.values.toList().map(_gpsCoordinatePart).toList();
}

double _gpsCoordinatePart(dynamic value) {
  if (value is Ratio) {
    return value.numerator / value.denominator;
  }
  return (value as num).toDouble();
}
