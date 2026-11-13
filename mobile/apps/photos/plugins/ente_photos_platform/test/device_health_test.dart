import 'package:ente_photos_platform/ente_photos_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validates native signal payloads', () {
    expect(
      DeviceHealthSnapshot.fromMap(_snapshotMap()).battery.levelPercent,
      64,
    );

    final invalidSnapshots = [
      _snapshotMap(battery: {'status': 'available'}),
      _snapshotMap(battery: {'status': 'unavailable'}),
      _snapshotMap(thermal: {'status': 'unsupported', 'state': 'nominal'}),
    ];

    for (final snapshot in invalidSnapshots) {
      expect(
        () => DeviceHealthSnapshot.fromMap(snapshot),
        throwsFormatException,
      );
    }
  });
}

Map<String, Object?> _snapshotMap({
  Map<String, Object?>? battery,
  Map<String, Object?>? thermal,
}) => {
  'platform': 'android',
  'observedAtMs': 1800000000000,
  'battery':
      battery ??
      {
        'status': 'available',
        'levelPercent': 64,
        'temperatureCelsius': 31.5,
        'health': 'good',
      },
  'thermal': thermal ?? {'status': 'available', 'state': 'moderate'},
};
