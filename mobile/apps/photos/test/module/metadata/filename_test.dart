import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/module/metadata/asset_date_times.dart";
import "package:photos/module/metadata/filename.dart";

void main() {
  group("filename dates", () {
    final date = DateTime(2024, 8, 31);
    final time = DateTime(2024, 8, 31, 12, 34, 56);
    final utc = DateTime.utc(2024, 8, 31, 12, 34, 56);
    final signalTime = DateTime(2026, 8, 31, 19, 55, 17);
    final millis = time.add(const Duration(milliseconds: 789));
    final tenths = time.add(const Duration(milliseconds: 100));
    const fraction = Duration(microseconds: 123456);
    final micros = time.add(fraction);
    final utcMicros = utc.add(fraction);
    final cases = {
      "IMG-20240831-WA0000": date,
      "Screenshot_20240831-123456_Firefox": time,
      "Screenshot_20240831-123456": time,
      "2024-08-31 12.34.56-DCMX.png": time,
      "20240831_123456": time,
      "2024-08-31 12.34.56": time,
      "IMG_20240831_123456": time,
      "2024-08-31 123456": time,
      "IMG_20240831_123456_783": time,
      "Screenshot_2024-08-31-12-34-56-164_newFormat.heic": time,
      "Screenshot 20240831 123456.com.google.android.apps.nbu.paisa.user.jpg":
          time,
      "signal-2024-08-31-12-34-56-718.jpg": time,
      "signal-2024-08-31-12-34-56-718-2.jpg": time,
      "signal-2026-08-31-195517.jpeg": signalTime,
      "signal-2026-08-31-195517-1.jpeg": signalTime,
      "signal-2026-08-31-195517.mp4": signalTime,
      "signal-2026-08-31-195517-12.mp4": signalTime,
      "PHOTO-2024-08-31-12-34-56.jpg": time,
      "PHOTO-2024-08-31-12-34-56-1.jpg": time,
      "2024-02-29 23:59:59.jpg": DateTime(2024, 2, 29, 23, 59, 59),
      "2000-02-29.jpg": DateTime(2000, 2, 29),
      "2024-08-31.jpg": date,
      "20240831.mp4": date,
      "IMG-20240831-WA0001.jpg": date,
      "IMG_2024.08.31_123456.jpg": time,
      "2024.02.29.jpg": DateTime(2024, 2, 29),
      "2024-08-31-edited.jpg": date,
      "IMG_20240831_HDR.jpg": date,
      "IMG_20240831_HDR": date,
      "2024-08-31 12:34:56,789.jpg": millis,
      "2024-08-31 12:34:56.1.jpg": tenths,
      "2024-08-31 12:34:56.123456.jpg": micros,
      "2024-08-31 14:34:56+02:00.jpg": utc,
      "2024-08-31 14:34:56+0200.jpg": utc,
      "2024-08-31 09:04:56-03:30.jpg": utc,
      "2024-08-31 09:04:56-0330.jpg": utc,
      "20240831T090456-0330.jpg": utc,
      "2024-08-31T09:04:56-0330.jpg": utc,
      "2024-08-31 09:04:56-0330-edited.jpg": utc,
      "2024-01-01 00:15:00+01:00.jpg": DateTime.utc(2023, 12, 31, 23, 15),
      "2024-01-01 23:45:00-0030.jpg": DateTime.utc(2024, 1, 2, 0, 15),
      "20240831T123456Z.jpg": utc,
      "20240831T123456z.jpg": utc,
      "2024-08-31 14:34:56.123456+02:00.jpg": utcMicros,
      "2024-08-31 09:04:56.123456-0330.jpg": utcMicros,
      "signal-2026-08-31-195517-0330.jpeg": signalTime,
      "signal-2026-08-31-195517-2460.jpeg": signalTime,
      "PHOTO-2024-08-31-12-34-56-0330.jpg": time,
    };
    for (final entry in cases.entries) {
      test("parses ${entry.key}", () {
        expect(parseDateTimeFromFileName(entry.key), entry.value);
      });
    }

    test("asset discovery strips numeric-leading media extensions", () {
      final dates = resolveAssetDateTimes(
        AssetEntity(
          id: "signal",
          typeInt: 2,
          width: 1920,
          height: 1080,
          title: "signal-2026-08-31-195517.3gp",
          createDateSecond: 0,
          modifiedDateSecond: 0,
        ),
      );
      expect(dates.creationTime, signalTime.microsecondsSinceEpoch);
    });

    for (final name in [
      "",
      "photo.jpg",
      "IMG_0123.JPG",
      "Snapchat-431959199.mp4.",
      "2023-02-29.jpg",
      "2023.02.29.jpg",
      "IMG_2024.08-31_195517.jpg",
      "IMG_2024.0831_195517.jpg",
      "2024-02-30.jpg",
      "2024-00-01.jpg",
      "2024-13-01.jpg",
      "2024-01-00.jpg",
      "2024-04-31.jpg",
      "2024-01-01-240000.jpg",
      "2024-01-01-126000.jpg",
      "2024-01-01-120060.jpg",
      "2024-01-01-12-34.jpg",
      "2024-01-01-12-34:56.jpg",
      "2024-01-01-1234567.jpg",
      "2024-0101-123456.jpg",
      "20240101-1.jpg",
      "120240101-123456.jpg",
      "2024a0101-123456.jpg",
      "IMG_20240101_1234.jpg",
      "IMG_20240101_HDR_1234.jpg",
      "2024-01-01-edited1234.jpg",
      "2024-01-01 12:34.jpg",
      "2024-01-01  12:34:56.jpg",
      "2024-01-01t12:34:56.jpg",
      "2024-01-01.123456.jpg",
      "20240101abcdef987654.jpg",
      "2024-01-01 12:34:56+24:00.jpg",
      "2024-01-01 12:34:56+02:60.jpg",
      "2024-01-01 12:34:56-24:00.jpg",
      "2024-01-01 12:34:56-02:60.jpg",
      "2024-01-01 12:34:56-2400.jpg",
      "2024-01-01 12:34:56-0260.jpg",
      "2024-01-01 12:34:56-03.jpg",
      "2024-01-01 12:34:56-03300.jpg",
      "2024-01-01 12:34:56+02:000.jpg",
      "2024-01-01 12:34:56+02.jpg",
      "2024-01-01 12:34:56,7890123.jpg",
      "2024-01-01 12:34:56.1234567.jpg",
      "2024-01-01 12:34:56,garbage.jpg",
      "2024-01-01 12:34:56 extra.jpg",
      "2024-01-01 12:34:56Zgarbage.jpg",
    ]) {
      test("rejects $name", () {
        expect(parseDateTimeFromFileName(name), isNull);
      });
    }

    test("respects year bounds", () {
      expect(parseDateTimeFromFileName("19891231.jpg"), isNull);
      expect(
        parseDateTimeFromFileName("19891231.jpg", minYear: 1980),
        DateTime(1989, 12, 31),
      );
      expect(
        parseDateTimeFromFileName("1900-02-29.jpg", minYear: 1900),
        isNull,
      );
      expect(parseDateTimeFromFileName("20260831.jpg", maxYear: 2025), isNull);
      expect(
        parseDateTimeFromFileName("20260831.jpg", maxYear: 2026),
        DateTime(2026, 8, 31),
      );
      final nextYear = currentYear + 1;
      expect(
        parseDateTimeFromFileName("$nextYear-01-01.jpg"),
        DateTime(nextYear, 1, 1),
      );
      expect(parseDateTimeFromFileName("${nextYear + 1}-01-01.jpg"), isNull);
    });
  });
}
