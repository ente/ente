import 'dart:convert';
import 'dart:io';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/openauthenticator_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otp/otp.dart' as otp;

import '../../../../helpers/rust.dart';

void main() {
  final skipReason = rustTestSkipReason;
  if (skipReason != null) {
    test('Rust import tests', () {}, skip: skipReason);
    return;
  }
  setUpAll(initializeTestRust);

  test('imports an Android 2.1.0 export', () async {
    final codes = await _importFixture('dummy');
    expect(
      codes.map(
        (code) => (
          code.issuer,
          code.account,
          code.secret,
          code.algorithm,
          code.digits,
          code.period,
        ),
      ),
      [
        (
          'Example',
          'team:alice +@例#/%',
          'MFRGGZDFMZTWQ2LK',
          Algorithm.sha512,
          8,
          30,
        ),
        (
          'Example',
          'user@example.com',
          'JBSWY3DPEHPK3PXP',
          Algorithm.sha1,
          6,
          30,
        ),
        ('GitHub', 'octocat', 'KRSXG5DSM5UQ', Algorithm.sha256, 8, 60),
      ],
    );
    expect(codes.every((code) => code.type == Type.totp), isTrue);
    expect(
      [
        for (final code in codes)
          for (final seconds in [59, 1111111109])
            otp.OTP.generateTOTPCodeString(
              code.secret,
              seconds * 1000,
              length: code.digits,
              interval: code.period,
              algorithm: otp.Algorithm.values.byName(
                code.algorithm.name.toUpperCase(),
              ),
              isGoogle: true,
            ),
      ],
      ['25413345', '70253442', '996554', '071271', '69151245', '66765760'],
    );
  });

  test('preserves accounts and defaults optional fields', () async {
    final backup = _fixtureMap();
    final entry = (backup['totps'] as List).first as Map;
    entry.remove('issuer');
    var code = (await _import(backup)).first;
    expect(code.account, 'team:alice +@例#/%');
    expect(code.issuer, isEmpty);

    for (final field in ['label', 'algorithm', 'digits', 'validity']) {
      entry.remove(field);
    }
    code = (await _import(backup)).first;
    expect(code.account, entry['uuid']);
    expect(code.algorithm, Algorithm.sha1);
    expect(code.digits, 6);
    expect(code.period, 30);
  });

  test('rejects an incorrect password', () async {
    await expectLater(
      _importFixture('not-dummy'),
      throwsA(isA<rust.ImportError_IncorrectPassword>()),
    );
  });

  test('validates backup structure without a password', () {
    expect(
      () => rust.validateOpenAuthenticator(input: _fixtureString()),
      returnsNormally,
    );
    final backup = _fixtureMap();
    backup.remove('totps');
    expect(
      () => rust.validateOpenAuthenticator(input: jsonEncode(backup)),
      throwsA(isA<rust.ImportError_Invalid>()),
    );
  });

  test(
    'reports corrupt entries without exposing them in native errors',
    () async {
      final backup = _fixtureMap();
      final entry = (backup['totps'] as List).first as Map;
      final bytes = entry['secret'] as List;
      bytes[0] = (bytes[0] as int) ^ 1;
      await expectLater(
        _import(backup),
        throwsA(isA<ImportEntryParseException>()),
      );
    },
  );

  test('rejects invalid explicit digit counts', () async {
    for (final digits in [null, '6', 0, -1, 11]) {
      final backup = _fixtureMap();
      ((backup['totps'] as List).first as Map)['digits'] = digits;
      await expectLater(
        _import(backup),
        throwsA(isA<ImportEntryParseException>()),
        reason: 'digits: $digits',
      );
    }
  });

  test('accepts an empty backup and rejects malformed backups', () async {
    final backup = _fixtureMap()..['totps'] = [];
    expect(await _import(backup), isEmpty);
    for (final input in ['not json', '[]', '{}']) {
      await expectLater(
        importOpenAuthenticatorExport(input, password: 'dummy'),
        throwsFormatException,
      );
    }
  });
}

String _fixtureString() => File(
  'test/ui/settings/data/import/fixtures/dummy-open-authenticator.bak',
).readAsStringSync();

Map<String, dynamic> _fixtureMap() =>
    jsonDecode(_fixtureString()) as Map<String, dynamic>;

Future<List<Code>> _importFixture(String password) =>
    importOpenAuthenticatorExport(_fixtureString(), password: password);

Future<List<Code>> _import(Map<String, dynamic> backup) =>
    importOpenAuthenticatorExport(jsonEncode(backup), password: 'dummy');
