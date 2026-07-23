import "package:photos/services/location_service.dart";
import "package:test/test.dart";

void main() {
  group('toLocationObj', () {
    test('returns null if lat or long are null', () {
      final gpsData = GPSData(null, null, null, null);
      expect(gpsData.toLocationObj(), isNull);

      final gpsDataWithLatOnly = GPSData(null, [1, 2, 3], null, null);
      expect(gpsDataWithLatOnly.toLocationObj(), isNull);

      final gpsDataWithLongOnly = GPSData(null, null, null, [1, 2, 3]);
      expect(gpsDataWithLongOnly.toLocationObj(), isNull);
    });

    test('returns null if lat or long have less than 3 elements', () {
      final gpsData1 = GPSData(null, [1, 2], null, [1, 2, 3]);
      expect(gpsData1.toLocationObj(), isNull);

      final gpsData2 = GPSData(null, [1, 2, 3], null, [1, 2]);
      expect(gpsData2.toLocationObj(), isNull);

      final gpsData3 = GPSData(null, [1, 2], null, [1, 2]);
      expect(gpsData3.toLocationObj(), isNull);
    });

    test('returns null if latRef or longRef is of invalid format', () {
      final gpsData1 = GPSData("A", [1, 2, 3], "xyz", [1, 2, 3]);
      expect(gpsData1.toLocationObj(), isNull);
    });

    void testParsingLocation(
      String? latRef,
      List<double> lat,
      String? longRef,
      List<double> long,
      double expectedLat,
      double expectedLong,
    ) {
      final gpsData = GPSData(latRef, lat, longRef, long);
      final location = gpsData.toLocationObj();
      expect(location, isNotNull);
      expect(location!.latitude, closeTo(expectedLat, 0.00001));
      expect(location.longitude, closeTo(expectedLong, 0.00001));
    }

    test(
      'converts coordinates with different latRef and longRef combinations',
      () {
        testParsingLocation(
          "N",
          [40, 26, 46.84],
          "E",
          [79, 58, 56.33],
          40.446344,
          79.982313,
        );
        testParsingLocation(
          "N",
          [40, 26, 46.84],
          "W",
          [79, 58, 56.33],
          40.446344,
          -79.982313,
        );
        testParsingLocation(
          "S",
          [40, 26, 46.84],
          "E",
          [79, 58, 56.33],
          -40.446344,
          79.982313,
        );
        testParsingLocation(
          "S",
          [40, 26, 46.84],
          "W",
          [79, 58, 56.33],
          -40.446344,
          -79.982313,
        );
      },
    );

    test(
      'converts coordinates with missing latRef and longRef but with signed lat and long',
      () {
        testParsingLocation(
          null,
          [40, 26, 46.84],
          null,
          [79, 58, 56.33],
          40.446344,
          79.982313,
        );
        testParsingLocation(
          null,
          [-40, 26, 46.84],
          null,
          [79, 58, 56.33],
          -40.446344,
          79.982313,
        );
        testParsingLocation(
          null,
          [40, 26, 46.84],
          null,
          [-79, 58, 56.33],
          40.446344,
          -79.982313,
        );
        testParsingLocation(
          null,
          [40, -26, 46.84],
          null,
          [79, -58, 56.33],
          -40.446344,
          -79.982313,
        );
      },
    );
  });
}
