import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ISO week boundaries', () {
    test('use Monday midnight regardless of the original time', () {
      final mondayMorning = DateTime(2026, 8, 17, 9);
      final sundayEvening = DateTime(2026, 8, 23, 18);

      expect(startOfISOWeek(mondayMorning), DateTime(2026, 8, 17));
      expect(startOfISOWeek(sundayEvening), DateTime(2026, 8, 17));
      expect(startOfNextISOWeek(mondayMorning), DateTime(2026, 8, 24));
      expect(startOfNextISOWeek(sundayEvening), DateTime(2026, 8, 24));
    });

    test('normalize weeks across year boundaries', () {
      final sunday = DateTime(2026, 1, 4, 23, 59, 59, 999, 999);

      expect(startOfISOWeek(sunday), DateTime(2025, 12, 29));
      expect(startOfNextISOWeek(sunday), DateTime(2026, 1, 5));
    });

    test('preserve UTC dates', () {
      final sunday = DateTime.utc(2026, 8, 23, 18);
      final start = startOfISOWeek(sunday);
      final nextStart = startOfNextISOWeek(sunday);

      expect(start, DateTime.utc(2026, 8, 17));
      expect(nextStart, DateTime.utc(2026, 8, 24));
      expect(start.isUtc, isTrue);
      expect(nextStart.isUtc, isTrue);
    });
  });

  test("parseDateTimeFromFile", () {
    final List<String> validParsing = [
      "IMG-20221109-WA0000",
      '''Screenshot_20220807-195908_Firefox''',
      '''Screenshot_20220507-195908''',
      "2022-02-18 16.00.12-DCMX.png",
      "20221107_231730",
      "2020-11-01 02.31.02",
      "IMG_20210921_144423",
      "2019-10-31 155703",
      "IMG_20210921_144423_783",
      "Screenshot_2022-06-21-16-51-29-164_newFormat.heic",
      "Screenshot 20221106 211633.com.google.android.apps.nbu.paisa.user.jpg",
      "signal-2022-12-17-15-16-04-718.jpg",
      "signal-2022-12-17-15-16-04-718-2.jpg",
    ];
    for (String val in validParsing) {
      final parsedValue = parseDateTimeFromFileNameV2(val);
      expect(
        parsedValue != null,
        true,
        reason: "Failed to parse time from $val",
      );
      if (kDebugMode) {
        debugPrint("Parsed $val as ${parsedValue?.toIso8601String()}");
      }
    }
  });

  test("test invalid datetime parsing", () {
    final List<String> badParsing = [
      "Snapchat-431959199.mp4.",
      "Snapchat-400000000.mp4",
      "Snapchat-900000000.mp4",
    ];
    for (String val in badParsing) {
      final parsedValue = parseDateTimeFromFileNameV2(val);
      expect(
        parsedValue == null,
        true,
        reason: "parsing should have failed $val",
      );
      if (kDebugMode) {
        debugPrint("Parsed $val as ${parsedValue?.toIso8601String()}");
      }
    }
  });
}
