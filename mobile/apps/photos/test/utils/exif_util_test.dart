import "package:exif_reader/exif_reader.dart";
import "package:photos/module/metadata/exif.dart";
import "package:test/test.dart";

void main() {
  group("getDateTimeInDeviceTimezone", () {
    test("parses standard EXIF date time", () {
      final parsed = getDateTimeInDeviceTimezone("2025:01:30 08:59:50", null);

      expect(parsed.dateTime, "2025-01-30T08:59:50.000");
      expect(parsed.offsetTime, isNull);
      expect(parsed.time.year, 2025);
      expect(parsed.time.month, 1);
      expect(parsed.time.day, 30);
      expect(parsed.time.hour, 8);
      expect(parsed.time.minute, 59);
      expect(parsed.time.second, 50);
    });

    test("parses standard EXIF date time with fractional seconds", () {
      final parsed = getDateTimeInDeviceTimezone(
        "2026:04:01 15:25:27.945",
        null,
      );

      expect(parsed.dateTime, "2026-04-01T15:25:27.945");
      expect(parsed.offsetTime, isNull);
      expect(parsed.time, DateTime(2026, 4, 1, 15, 25, 27, 945));
    });

    test("parses standard EXIF date time with separate offset", () {
      final parsed = getDateTimeInDeviceTimezone(
        "2025:01:30 08:59:50",
        "+01:00",
      );

      expect(parsed.dateTime, "2025-01-30T08:59:50.000");
      expect(parsed.offsetTime, "+01:00");
      expect(parsed.time.toUtc(), DateTime.utc(2025, 1, 30, 7, 59, 50));
    });

    test("parses standard EXIF date time with compact separate offset", () {
      final parsed = getDateTimeInDeviceTimezone(
        "2025:01:30 08:59:50",
        "+0530",
      );

      expect(parsed.dateTime, "2025-01-30T08:59:50.000");
      expect(parsed.offsetTime, "+05:30");
      expect(parsed.time.toUtc(), DateTime.utc(2025, 1, 30, 3, 29, 50));
    });

    test("drops invalid separate offset for standard EXIF date time", () {
      final parsed = getDateTimeInDeviceTimezone(
        "2025:01:30 08:59:50",
        "    :  ",
      );

      expect(parsed.dateTime, "2025-01-30T08:59:50.000");
      expect(parsed.offsetTime, isNull);
      expect(parsed.time, DateTime(2025, 1, 30, 8, 59, 50));
    });

    test("drops invalid separate offset for fractional EXIF date time", () {
      final parsed = getDateTimeInDeviceTimezone(
        "2026:04:01 15:25:27.945",
        "CDT",
      );

      expect(parsed.dateTime, "2026-04-01T15:25:27.945");
      expect(parsed.offsetTime, isNull);
      expect(parsed.time, DateTime(2026, 4, 1, 15, 25, 27, 945));
    });

    test("parses ISO date time with numeric offset", () {
      final parsed = getDateTimeInDeviceTimezone(
        "2025-01-30T08:59:50+01:00",
        null,
      );

      expect(parsed.dateTime, "2025-01-30T08:59:50.000");
      expect(parsed.offsetTime, "+01:00");
      expect(parsed.time.toUtc(), DateTime.utc(2025, 1, 30, 7, 59, 50));
    });

    test("parses ISO date time with compact numeric offset", () {
      final parsed = getDateTimeInDeviceTimezone(
        "2025-01-30T08:59:50+0530",
        null,
      );

      expect(parsed.dateTime, "2025-01-30T08:59:50.000");
      expect(parsed.offsetTime, "+05:30");
      expect(parsed.time.toUtc(), DateTime.utc(2025, 1, 30, 3, 29, 50));
    });

    test("parses ISO date time with half-hour numeric offset", () {
      final parsed = getDateTimeInDeviceTimezone(
        "2024-04-01T19:17:29+05:30",
        null,
      );

      expect(parsed.dateTime, "2024-04-01T19:17:29.000");
      expect(parsed.offsetTime, "+05:30");
      expect(parsed.time.toUtc(), DateTime.utc(2024, 4, 1, 13, 47, 29));
    });

    test("parses ISO date time with separate numeric offset", () {
      final parsed = getDateTimeInDeviceTimezone(
        "2025-01-30T08:59:50",
        "+01:00",
      );

      expect(parsed.dateTime, "2025-01-30T08:59:50.000");
      expect(parsed.offsetTime, "+01:00");
      expect(parsed.time.toUtc(), DateTime.utc(2025, 1, 30, 7, 59, 50));
    });

    test("parses ISO date time with compact separate numeric offset", () {
      final parsed = getDateTimeInDeviceTimezone(
        "2025-01-30T08:59:50",
        "+0530",
      );

      expect(parsed.dateTime, "2025-01-30T08:59:50.000");
      expect(parsed.offsetTime, "+05:30");
      expect(parsed.time.toUtc(), DateTime.utc(2025, 1, 30, 3, 29, 50));
    });

    test("drops invalid separate offset for ISO date time", () {
      final parsed = getDateTimeInDeviceTimezone("2025-01-30T08:59:50", "CDT");

      expect(parsed.dateTime, "2025-01-30T08:59:50.000");
      expect(parsed.offsetTime, isNull);
      expect(parsed.time, DateTime(2025, 1, 30, 8, 59, 50));
    });

    test("parses ISO date time with Z offset", () {
      final parsed = getDateTimeInDeviceTimezone("2026-04-20T00:00:00Z", null);

      expect(parsed.dateTime, "2026-04-20T00:00:00.000");
      expect(parsed.offsetTime, "Z");
      expect(parsed.time.toUtc(), DateTime.utc(2026, 4, 20));
    });

    test("parses ISO date time with space separator and no offset", () {
      final parsed = getDateTimeInDeviceTimezone("2025-11-12 15:12:01", null);

      expect(parsed.dateTime, "2025-11-12T15:12:01.000");
      expect(parsed.offsetTime, isNull);
      expect(parsed.time.year, 2025);
      expect(parsed.time.month, 11);
      expect(parsed.time.day, 12);
      expect(parsed.time.hour, 15);
      expect(parsed.time.minute, 12);
      expect(parsed.time.second, 1);
      expect(parsed.time.isUtc, isFalse);
    });

    test("parses date time with colon-separated milliseconds", () {
      final parsed = getDateTimeInDeviceTimezone(
        "2019-11-28 14:38:40:794",
        null,
      );

      expect(parsed.dateTime, "2019-11-28T14:38:40.794");
      expect(parsed.offsetTime, isNull);
      expect(parsed.time.year, 2019);
      expect(parsed.time.month, 11);
      expect(parsed.time.day, 28);
      expect(parsed.time.hour, 14);
      expect(parsed.time.minute, 38);
      expect(parsed.time.second, 40);
      expect(parsed.time.millisecond, 794);
    });

    test("does not guess timezone abbreviations", () {
      expect(
        () => getDateTimeInDeviceTimezone("2024-09-07T16:29:28CDT", null),
        throwsFormatException,
      );
    });

    test("rejects trailing data in standard EXIF date time", () {
      expect(
        () => getDateTimeInDeviceTimezone("2024:09:07 16:29:28CDT", null),
        throwsFormatException,
      );
      expect(
        () => getDateTimeInDeviceTimezone("2024:09:07 16:29:28+05:30", null),
        throwsFormatException,
      );
    });

    test("rejects invalid standard EXIF date time components", () {
      expect(
        () => getDateTimeInDeviceTimezone("2025:02:30 08:00:00.945", null),
        throwsFormatException,
      );
    });

    test("rejects invalid ISO date time components", () {
      expect(
        () => getDateTimeInDeviceTimezone("2025-02-30T08:00:00Z", null),
        throwsFormatException,
      );
      expect(
        () => getDateTimeInDeviceTimezone("2025-01-30T24:00:00+01:00", null),
        throwsFormatException,
      );
      expect(
        () => getDateTimeInDeviceTimezone("2025-01-30T08:00:00+99:99", null),
        throwsFormatException,
      );
    });
  });

  group("tryParseExifDateTime", () {
    test("ignores invalid date values from file metadata", () async {
      final parsed = await tryParseExifDateTime(null, {
        kDateTimeOriginal: _ifdTag(
          const IfdNone(),
          printable: "2025:12:13 14:24:60",
        ),
      });

      expect(parsed, isNull);
    });
  });

  group("gpsDataFromExif", () {
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
  });
}

IfdTag _ifdTag(IfdValues values, {String printable = ""}) {
  return IfdTag(tag: 0, tagType: "", printable: printable, values: values);
}
