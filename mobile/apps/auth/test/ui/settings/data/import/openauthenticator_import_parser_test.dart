import 'dart:convert';
import 'dart:io';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/openauthenticator_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Open Authenticator import parser', () {
    test('decrypts a backup with the correct password', () {
      final codes = parseOpenAuthenticatorEntries(
        _decryptFixture(password: 'dummy'),
      );

      expect(codes, hasLength(5));
      _expectCode(
        codes[0],
        issuer: 'Example',
        account: 'user@example.com',
        secret: 'JBSWY3DPEHPK3PXP',
        algorithm: Algorithm.sha1,
        digits: 6,
        period: 30,
      );
      _expectCode(
        codes[1],
        issuer: 'GitHub',
        account: 'octocat',
        secret: 'KRSXG5DSM5UQ',
        algorithm: Algorithm.sha256,
        digits: 8,
        period: 60,
      );
      _expectCode(
        codes[2],
        issuer: '',
        account: 'justlabel@example.org',
        secret: 'MFRGGZDFMZTWQ2LK',
        algorithm: Algorithm.sha1,
        digits: 6,
        period: 30,
      );
      _expectCode(
        codes[3],
        issuer: '',
        account: '44444444-4444-4444-8444-444444444444',
        secret: 'GEZDGNBVGY3TQOJQ',
        algorithm: Algorithm.sha1,
        digits: 6,
        period: 30,
      );
      _expectCode(
        codes[4],
        issuer: 'Legacy',
        account: 'old-salt',
        secret: 'ONSWG4TFOQ',
        algorithm: Algorithm.sha1,
        digits: 6,
        period: 30,
      );
    });

    test('preserves non-default algorithm, digits and period', () {
      final codes = parseOpenAuthenticatorEntries(
        _decryptFixture(password: 'dummy'),
      );

      expect(codes[1].algorithm, Algorithm.sha256);
      expect(codes[1].digits, 8);
      expect(codes[1].period, 60);
    });

    test('uses the uuid as the account when the label is missing', () {
      final codes = parseOpenAuthenticatorEntries(
        _decryptFixture(password: 'dummy'),
      );

      expect(codes[3].account, '44444444-4444-4444-8444-444444444444');
      expect(codes[3].issuer, isEmpty);
    });

    test('preserves colons in labels without an issuer', () {
      final codes = parseOpenAuthenticatorEntries([
        {
          'secret': 'JBSWY3DPEHPK3PXP',
          'label': 'team:alice',
          'algorithm': 'SHA1',
          'digits': 6,
          'validity': 30,
        },
      ]);

      expect(codes.single.account, 'team:alice');
      expect(codes.single.issuer, isEmpty);
    });

    test('rejects an unsupported explicit digit count', () {
      final backup = decodeOpenAuthenticatorBackup(_fixtureContent());
      final firstEntry = (backup['totps'] as List).first as Map;
      firstEntry['digits'] = 11;

      expect(
        () => decryptOpenAuthenticatorBackup(backup, password: 'dummy'),
        throwsA(isA<OpenAuthenticatorEntryParseException>()),
      );
    });

    test(
      'falls back to an entry encryptionSalt that differs from the backup',
      () {
        // Entry 5555 was encrypted with a different salt than the backup.
        final codes = parseOpenAuthenticatorEntries(
          _decryptFixture(password: 'dummy'),
        );

        expect(codes[4].secret, 'ONSWG4TFOQ');
        expect(codes[4].issuer, 'Legacy');
      },
    );

    test('ignores the imageUrl field', () {
      final codes = parseOpenAuthenticatorEntries(
        _decryptFixture(password: 'dummy'),
      );

      expect(codes[0].display.isCustomIcon, isFalse);
    });

    test('rejects a present optional field that fails authentication', () {
      final backup = decodeOpenAuthenticatorBackup(_fixtureContent());
      final firstEntry = (backup['totps'] as List).first as Map;
      final label = firstEntry['label'] as List;
      label[0] = (label[0] as int) ^ 1;

      expect(
        () => decryptOpenAuthenticatorBackup(backup, password: 'dummy'),
        throwsA(isA<OpenAuthenticatorEntryParseException>()),
      );
    });

    test('rejects a wrong password', () {
      final backup = decodeOpenAuthenticatorBackup(_fixtureContent());

      expect(
        () => decryptOpenAuthenticatorBackup(backup, password: 'not-dummy'),
        throwsA(isA<IncorrectOpenAuthenticatorPasswordException>()),
      );
    });

    test('rejects an invalid salt before password verification', () {
      final backup = decodeOpenAuthenticatorBackup(_fixtureContent())
        ..['salt'] = 'not-base64';

      expect(
        () => decodeOpenAuthenticatorBackup(jsonEncode(backup)),
        throwsA(isA<InvalidOpenAuthenticatorBackupException>()),
      );
    });

    test('rejects malformed backups', () {
      const invalidBackups = <String>[
        'not json',
        '[]',
        '{}',
        '{"salt": "AA==", "totps": []}',
        '{"salt": "AA==", "passwordSignature": "x", "totps": []}',
        '{"salt": "AA==", "passwordSignature": "AA==", "totps": []}',
        '{"salt": "AA==", "passwordSignature": "x", "totps": "nope"}',
      ];

      for (final backup in invalidBackups) {
        expect(
          () => decodeOpenAuthenticatorBackup(backup),
          throwsA(isA<InvalidOpenAuthenticatorBackupException>()),
          reason: 'Should reject: $backup',
        );
      }
    });
  });
}

List<Map<String, Object?>> _decryptFixture({required String password}) {
  final backup = decodeOpenAuthenticatorBackup(_fixtureContent());
  return decryptOpenAuthenticatorBackup(backup, password: password);
}

String _fixtureContent() => File(
  'test/ui/settings/data/import/fixtures/dummy-open-authenticator.bak',
).readAsStringSync();

void _expectCode(
  Code code, {
  required String issuer,
  required String account,
  required String secret,
  required Algorithm algorithm,
  required int digits,
  required int period,
}) {
  expect(code.type, Type.totp);
  expect(code.issuer, issuer);
  expect(code.account, account);
  expect(code.secret, secret);
  expect(code.algorithm, algorithm);
  expect(code.digits, digits);
  expect(code.period, period);
}
