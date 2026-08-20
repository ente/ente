import "package:photos/services/location_service.dart";
import "package:test/test.dart";

void main() {
  group('toLocationObj', () {
    test('rejects incomplete coordinates and invalid references', () {
      for (final gpsData in [
        GPSData(null, null, null, null),
        GPSData(null, [1, 2, 3], null, null),
        GPSData(null, null, null, [1, 2, 3]),
        GPSData(null, [1, 2], null, [1, 2, 3]),
        GPSData(null, [1, 2, 3], null, [1, 2]),
        GPSData(null, [1, 2], null, [1, 2]),
        GPSData("A", [1, 2, 3], "xyz", [1, 2, 3]),
      ]) {
        expect(gpsData.toLocationObj(), isNull);
      }
    });

    for (final (name, latRef, lat, longRef, long, expectedLat, expectedLong)
        in const [
          (
            'north east',
            'N',
            [40.0, 26.0, 46.84],
            'E',
            [79.0, 58.0, 56.33],
            40.446344,
            79.982313,
          ),
          (
            'north west',
            'N',
            [40.0, 26.0, 46.84],
            'W',
            [79.0, 58.0, 56.33],
            40.446344,
            -79.982313,
          ),
          (
            'south east',
            'S',
            [40.0, 26.0, 46.84],
            'E',
            [79.0, 58.0, 56.33],
            -40.446344,
            79.982313,
          ),
          (
            'south west',
            'S',
            [40.0, 26.0, 46.84],
            'W',
            [79.0, 58.0, 56.33],
            -40.446344,
            -79.982313,
          ),
          (
            'unsigned without references',
            null,
            [40.0, 26.0, 46.84],
            null,
            [79.0, 58.0, 56.33],
            40.446344,
            79.982313,
          ),
          (
            'negative latitude without references',
            null,
            [-40.0, 26.0, 46.84],
            null,
            [79.0, 58.0, 56.33],
            -40.446344,
            79.982313,
          ),
          (
            'negative longitude without references',
            null,
            [40.0, 26.0, 46.84],
            null,
            [-79.0, 58.0, 56.33],
            40.446344,
            -79.982313,
          ),
          (
            'negative minutes without references',
            null,
            [40.0, -26.0, 46.84],
            null,
            [79.0, -58.0, 56.33],
            -40.446344,
            -79.982313,
          ),
        ]) {
      test(name, () {
        final location = GPSData(
          latRef,
          [...lat],
          longRef,
          [...long],
        ).toLocationObj();

        expect(location, isNotNull);
        expect(location!.latitude, closeTo(expectedLat, 0.00001));
        expect(location.longitude, closeTo(expectedLong, 0.00001));
      });
    }
  });
}
