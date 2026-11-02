import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('baseUrlForLogging', () {
    test('retains scheme, host and port without sensitive URL components', () {
      const cases = {
        'ente://passkey?response=SYNTHETIC_RESPONSE#SYNTHETIC_FRAGMENT':
            'ente://passkey',
        'enteauth://passkey?response=SYNTHETIC_RESPONSE': 'enteauth://passkey',
        'entelocker://passkey?response=SYNTHETIC_RESPONSE':
            'entelocker://passkey',
        'ente://SYNTHETIC_USER:SYNTHETIC_PASSWORD@passkey:8443/SYNTHETIC_PATH?response=SYNTHETIC_RESPONSE#SYNTHETIC_FRAGMENT':
            'ente://passkey:8443',
        'https://SYNTHETIC_USER:SYNTHETIC_PASSWORD@example.test:8443/SYNTHETIC_PATH?response=SYNTHETIC_RESPONSE#SYNTHETIC_FRAGMENT':
            'https://example.test:8443',
        'https://[::1]:8443/SYNTHETIC_PATH?response=SYNTHETIC_RESPONSE#SYNTHETIC_FRAGMENT':
            'https://[::1]:8443',
        'HTTPS://EXAMPLE.TEST:443/SYNTHETIC_PATH': 'https://example.test',
      };
      for (final entry in cases.entries) {
        expect(baseUrlForLogging(entry.key), entry.value, reason: entry.key);
      }
    });

    test('returns a generic fallback when a base URL cannot be extracted', () {
      const cases = [
        '',
        'SYNTHETIC_PRIVATE_DATA',
        '//example.test?response=SYNTHETIC_RESPONSE',
        'ente:SYNTHETIC_PRIVATE_DATA',
        'https://example.test:SYNTHETIC_PRIVATE_DATA',
        'https://[SYNTHETIC_PRIVATE_DATA',
        'https://example.test:999999999999999999999/SYNTHETIC_PRIVATE_DATA',
      ];
      for (final value in cases) {
        expect(baseUrlForLogging(value), 'unknown URL', reason: value);
      }
    });
  });
}
