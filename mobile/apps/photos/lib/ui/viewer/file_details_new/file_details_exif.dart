import "package:exif_reader/exif_reader.dart";

class FileDetailsExif {
  const FileDetailsExif._({
    this.focalLength,
    this.fNumber,
    this.resolution,
    this.takenOnDevice,
    this.exposureTime,
    this.iso,
    this.megaPixels,
  });

  factory FileDetailsExif.fromTags(Map<String, IfdTag> exif) {
    double? focalLength;
    final focalLengthTag = exif["EXIF FocalLength"];
    if (focalLengthTag != null) {
      final ratio = focalLengthTag.values.toList()[0] as Ratio;
      focalLength = ratio.numerator / ratio.denominator;
    }

    double? fNumber;
    final fNumberTag = exif["EXIF FNumber"];
    if (fNumberTag != null) {
      final ratio = fNumberTag.values.toList()[0] as Ratio;
      fNumber = ratio.numerator / ratio.denominator;
    }

    final imageWidth = _firstPositiveDimensionTag(exif, const [
      "EXIF ExifImageWidth",
      "Image ImageWidth",
    ]);
    final imageLength = _firstPositiveDimensionTag(exif, const [
      "EXIF ExifImageLength",
      "Image ImageLength",
    ]);

    String? resolution;
    double? megaPixels;
    if (imageWidth != null && imageLength != null) {
      resolution = "$imageWidth x $imageLength";
      final value =
          (imageWidth.values.firstAsInt() * imageLength.values.firstAsInt()) /
          1000000;
      megaPixels = (value * 10).round() / 10.0;
    }

    String? takenOnDevice;
    if (exif["Image Make"] != null && exif["Image Model"] != null) {
      takenOnDevice =
          exif["Image Make"].toString() + " " + exif["Image Model"].toString();
    }

    return FileDetailsExif._(
      focalLength: focalLength,
      fNumber: fNumber,
      resolution: resolution,
      takenOnDevice: takenOnDevice,
      exposureTime: exif["EXIF ExposureTime"] == null
          ? null
          : _formatExposureTime(exif["EXIF ExposureTime"]!),
      iso: exif["EXIF ISOSpeedRatings"]?.toString(),
      megaPixels: megaPixels,
    );
  }

  final double? focalLength;
  final double? fNumber;
  final String? resolution;
  final String? takenOnDevice;
  final String? exposureTime;
  final String? iso;
  final double? megaPixels;

  bool get hasBasicData =>
      focalLength != null ||
      fNumber != null ||
      takenOnDevice != null ||
      exposureTime != null ||
      iso != null;

  static IfdTag? _firstPositiveDimensionTag(
    Map<String, IfdTag> exif,
    List<String> keys,
  ) {
    for (final key in keys) {
      final tag = exif[key];
      if (tag != null && tag.values.firstAsInt() > 0) return tag;
    }
    return null;
  }

  static String _formatExposureTime(IfdTag tag) {
    final values = tag.values.toList();
    if (values.isEmpty || values.first is! Ratio) return tag.toString();
    final ratio = values.first as Ratio;
    if (ratio.denominator == 0) return tag.toString();
    final seconds = ratio.numerator / ratio.denominator;
    if (seconds >= 1) {
      return seconds == seconds.roundToDouble()
          ? "${seconds.toInt()}s"
          : "${seconds.toStringAsFixed(1)}s";
    }
    return "1/${(1 / seconds).round()}";
  }
}
