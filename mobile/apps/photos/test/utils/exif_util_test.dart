import "package:exif_reader/exif_reader.dart";
import "package:photos/module/metadata/exif.dart";
import "package:test/test.dart";

void main() {
  group("getDateTimeInDeviceTimezone", () {
    for (final (name, input, offset, dateTime, offsetTime, time) in [
      (
        "standard EXIF date time",
        "2025:01:30 08:59:50",
        null,
        "2025-01-30T08:59:50.000",
        null,
        DateTime(2025, 1, 30, 8, 59, 50),
      ),
      (
        "fractional EXIF seconds",
        "2026:04:01 15:25:27.945",
        null,
        "2026-04-01T15:25:27.945",
        null,
        DateTime(2026, 4, 1, 15, 25, 27, 945),
      ),
      (
        "separate EXIF offset",
        "2025:01:30 08:59:50",
        "+01:00",
        "2025-01-30T08:59:50.000",
        "+01:00",
        DateTime.utc(2025, 1, 30, 7, 59, 50),
      ),
      (
        "compact separate EXIF offset",
        "2025:01:30 08:59:50",
        "+0530",
        "2025-01-30T08:59:50.000",
        "+05:30",
        DateTime.utc(2025, 1, 30, 3, 29, 50),
      ),
      (
        "invalid separate EXIF offset",
        "2025:01:30 08:59:50",
        "    :  ",
        "2025-01-30T08:59:50.000",
        null,
        DateTime(2025, 1, 30, 8, 59, 50),
      ),
      (
        "invalid fractional EXIF offset",
        "2026:04:01 15:25:27.945",
        "CDT",
        "2026-04-01T15:25:27.945",
        null,
        DateTime(2026, 4, 1, 15, 25, 27, 945),
      ),
      (
        "ISO numeric offset",
        "2025-01-30T08:59:50+01:00",
        null,
        "2025-01-30T08:59:50.000",
        "+01:00",
        DateTime.utc(2025, 1, 30, 7, 59, 50),
      ),
      (
        "ISO compact numeric offset",
        "2025-01-30T08:59:50+0530",
        null,
        "2025-01-30T08:59:50.000",
        "+05:30",
        DateTime.utc(2025, 1, 30, 3, 29, 50),
      ),
      (
        "ISO half-hour offset",
        "2024-04-01T19:17:29+05:30",
        null,
        "2024-04-01T19:17:29.000",
        "+05:30",
        DateTime.utc(2024, 4, 1, 13, 47, 29),
      ),
      (
        "ISO separate numeric offset",
        "2025-01-30T08:59:50",
        "+01:00",
        "2025-01-30T08:59:50.000",
        "+01:00",
        DateTime.utc(2025, 1, 30, 7, 59, 50),
      ),
      (
        "ISO compact separate numeric offset",
        "2025-01-30T08:59:50",
        "+0530",
        "2025-01-30T08:59:50.000",
        "+05:30",
        DateTime.utc(2025, 1, 30, 3, 29, 50),
      ),
      (
        "invalid separate ISO offset",
        "2025-01-30T08:59:50",
        "CDT",
        "2025-01-30T08:59:50.000",
        null,
        DateTime(2025, 1, 30, 8, 59, 50),
      ),
      (
        "ISO Z offset",
        "2026-04-20T00:00:00Z",
        null,
        "2026-04-20T00:00:00.000",
        "Z",
        DateTime.utc(2026, 4, 20),
      ),
      (
        "ISO space separator",
        "2025-11-12 15:12:01",
        null,
        "2025-11-12T15:12:01.000",
        null,
        DateTime(2025, 11, 12, 15, 12, 1),
      ),
      (
        "colon-separated milliseconds",
        "2019-11-28 14:38:40:794",
        null,
        "2019-11-28T14:38:40.794",
        null,
        DateTime(2019, 11, 28, 14, 38, 40, 794),
      ),
    ]) {
      test(name, () {
        final parsed = getDateTimeInDeviceTimezone(input, offset);

        expect(parsed.dateTime, dateTime);
        expect(parsed.offsetTime, offsetTime);
        expect(time.isUtc ? parsed.time.toUtc() : parsed.time, time);
      });
    }

    for (final input in [
      "2024-09-07T16:29:28CDT",
      "2024:09:07 16:29:28CDT",
      "2024:09:07 16:29:28+05:30",
      "2025:02:30 08:00:00.945",
      "2025-02-30T08:00:00Z",
      "2025-01-30T24:00:00+01:00",
      "2025-01-30T08:00:00+99:99",
    ]) {
      test("rejects $input", () {
        expect(
          () => getDateTimeInDeviceTimezone(input, null),
          throwsFormatException,
        );
      });
    }
  });

  test("ignores invalid date values from file metadata", () async {
    final parsed = await tryParseExifDateTime(null, {
      kDateTimeOriginal: _ifdTag(
        const IfdNone(),
        printable: "2025:12:13 14:24:60",
      ),
    });

    expect(parsed, isNull);
  });

  test("parses integer GPS coordinate parts", () {
    final gpsData = gpsDataFromExif({
      "GPS GPSLatitude": _ifdTag(const IfdInts([40, 26, 46])),
      "GPS GPSLatitudeRef": _ifdTag(const IfdInts([0]), printable: "N"),
      "GPS GPSLongitude": _ifdTag(const IfdInts([79, 58, 56])),
      "GPS GPSLongitudeRef": _ifdTag(const IfdInts([0]), printable: "W"),
    });

    final location = gpsData.toLocationObj();

    expect(location, isNotNull);
    expect(location!.latitude, closeTo(40.446111, 0.000001));
    expect(location.longitude, closeTo(-79.982222, 0.000001));
  });
}

IfdTag _ifdTag(IfdValues values, {String printable = ""}) {
  return IfdTag(tag: 0, tagType: "", printable: printable, values: values);
}
