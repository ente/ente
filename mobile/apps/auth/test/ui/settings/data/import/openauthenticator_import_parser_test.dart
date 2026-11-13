import 'dart:convert';
import 'dart:io';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/openauthenticator_import_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otp/otp.dart' as otp;

void main() {
  test('imports an Android 2.1.0 export in a background isolate', () async {
    final codes = await compute(_decryptFixture, 'dummy');
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
    expect(codes.every((code) => !code.display.isCustomIcon), isTrue);
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

  test('preserves colons and URI characters in an issuer-less account', () {
    final backup = _fixture();
    final entry = (backup['totps'] as List).first as Map;
    entry.remove('issuer');
    final code = decryptOpenAuthenticatorBackup(
      backup,
      password: 'dummy',
    ).first;
    expect(code.account, 'team:alice +@例#/%');
    expect(code.issuer, isEmpty);
  });

  test('uses the UUID and defaults for omitted optional fields', () {
    final backup = _fixture();
    final entry = (backup['totps'] as List).first as Map;
    for (final field in [
      'label',
      'issuer',
      'algorithm',
      'digits',
      'validity',
    ]) {
      entry.remove(field);
    }
    final code = decryptOpenAuthenticatorBackup(
      backup,
      password: 'dummy',
    ).first;
    expect(code.account, entry['uuid']);
    expect(code.issuer, isEmpty);
    expect(code.algorithm, Algorithm.sha1);
    expect(code.digits, 6);
    expect(code.period, 30);
  });

  test('rejects entries encrypted under another key', () {
    final backup = _fixture();
    final entry = (backup['totps'] as List).last as Map;
    entry.remove('label');
    entry.remove('issuer');
    entry['encryptionSalt'] = List.filled(32, 34);
    entry['secret'] = base64Decode(
      '0bsWmTM88NTfjCM227siiMmmBf8fhsWO53EyxvN5fJ4CzgIfn60=',
    );
    expect(
      () => decryptOpenAuthenticatorBackup(backup, password: 'dummy'),
      throwsA(isA<ImportEntryParseException>()),
    );
  });

  test('rejects invalid explicit digit counts', () {
    for (final digits in [null, '6', 0, -1, 11]) {
      final backup = _fixture();
      ((backup['totps'] as List).first as Map)['digits'] = digits;
      expect(
        () => decryptOpenAuthenticatorBackup(backup, password: 'dummy'),
        throwsA(isA<ImportEntryParseException>()),
        reason: 'digits: $digits',
      );
    }
  });

  test(
    'reports corrupt encrypted fields with their entry across isolates',
    () async {
      for (final field in ['secret', 'label', 'issuer']) {
        final backup = _fixture();
        final entry = (backup['totps'] as List).first as Map;
        final bytes = entry[field] as List;
        bytes[0] = (bytes[0] as int) ^ 1;
        await expectLater(
          compute(_decryptBackup, backup),
          throwsA(
            isA<ImportEntryParseException>().having(
              (error) => error.entry,
              'entry',
              entry,
            ),
          ),
          reason: field,
        );
      }
    },
  );

  test('rejects malformed entries and byte arrays', () {
    for (final entry in [
      null,
      <String, Object?>{},
      for (final secret in [
        null,
        'secret',
        [],
        [-1],
        [256],
        ['0'],
      ])
        {'secret': secret},
      for (final field in ['label', 'issuer'])
        <String, dynamic>{
          ...((_fixture()['totps'] as List).first as Map<String, dynamic>),
          field: null,
        },
    ]) {
      final backup = _fixture()..['totps'] = [entry];
      expect(
        () => decryptOpenAuthenticatorBackup(backup, password: 'dummy'),
        throwsA(isA<ImportEntryParseException>()),
      );
    }
  });

  test('reports an incorrect password across isolates', () async {
    await expectLater(
      compute(_decryptFixture, 'not-dummy'),
      throwsA(isA<IncorrectOpenAuthenticatorPasswordException>()),
    );
  });

  test('accepts an empty backup', () {
    final backup = _fixture()..['totps'] = [];
    expect(decryptOpenAuthenticatorBackup(backup, password: 'dummy'), isEmpty);
  });

  test('rejects malformed backups before password verification', () {
    for (final content in [
      'not json',
      '[]',
      '{}',
      jsonEncode(_fixture()..['totps'] = 'invalid'),
      for (final field in ['salt', 'passwordSignature'])
        for (final value in [null, 'not-base64', 'AA=='])
          jsonEncode(_fixture()..[field] = value),
    ]) {
      expect(
        () => decodeOpenAuthenticatorBackup(content),
        throwsFormatException,
      );
    }
  });
}

Map<String, dynamic> _fixture() => decodeOpenAuthenticatorBackup(
  File(
    'test/ui/settings/data/import/fixtures/dummy-open-authenticator.bak',
  ).readAsStringSync(),
);

List<Code> _decryptFixture(String password) =>
    decryptOpenAuthenticatorBackup(_fixture(), password: password);

List<Code> _decryptBackup(Map<String, dynamic> backup) =>
    decryptOpenAuthenticatorBackup(backup, password: 'dummy');
