import 'dart:convert';
import 'dart:io';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/proton_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/rust.dart';

void main() {
  final skipReason = rustTestSkipReason;
  if (skipReason != null) {
    test('Rust import tests', () {}, skip: skipReason);
    return;
  }
  setUpAll(initializeTestRust);

  group('Proton import parser', () {
    test('parses plaintext Proton exports from fixture', () async {
      final codes = await _loadPlaintextFixtureCodes();

      const expectedCodes = <_ExpectedCode>[
        (
          issuer: '.env',
          account: 'example@ente.io',
          secret: 'MI4GCOJSGIZTKLJSGMZWKLJUGEZDQLJYG5STILJSMUYDIYTCMQ3TSOJRGI',
        ),
        (issuer: '/e/', account: 'cool@ente.com', secret: '554VBDOGJRLDG2JV'),
        (
          issuer: 'ente',
          account: 'simple@ente.sh',
          secret: 'PIBTGMBYQYVSLN5PVZYQUTKYHOBRYYT7',
        ),
        (
          issuer: 'reddit',
          account: 'r@ente.com',
          secret: 'J4YFC3TZKVYWCVCNIVBWIV2GHFAXUNDF',
        ),
      ];

      expect(codes, hasLength(expectedCodes.length));
      for (var index = 0; index < expectedCodes.length; index++) {
        _expectCode(codes[index], expectedCodes[index]);
      }
    });

    test('decrypts password protected Proton exports from fixture', () async {
      final decryptedCodes = await importProtonExport(
        await _fixture(
          'proton_authenticator_backup_encrypted_1231246.json',
        ).readAsString(),
        password: '1231246',
      );
      final plaintextCodes = await _loadPlaintextFixtureCodes();

      expect(decryptedCodes, hasLength(4));
      expect(decryptedCodes, hasLength(plaintextCodes.length));
      for (var index = 0; index < plaintextCodes.length; index++) {
        expect(decryptedCodes[index], plaintextCodes[index]);
      }
    });

    test(
      'fails to decrypt password protected Proton exports with bad password',
      () async {
        await expectLater(
          importProtonExport(
            await _fixture(
              'proton_authenticator_backup_encrypted_1231246.json',
            ).readAsString(),
            password: 'wrong-password',
          ),
          throwsA(isA<rust.ImportError_IncorrectPassword>()),
        );
      },
    );
  });
}

Future<List<Code>> _loadPlaintextFixtureCodes() async {
  return importProtonExport(
    await _fixture('proton_authenticator_backup.json').readAsString(),
  );
}

void _expectCode(Code code, _ExpectedCode expected) {
  expect(code.type, Type.totp);
  expect(code.issuer, expected.issuer);
  expect(code.account, expected.account);
  expect(code.secret, expected.secret);
  expect(code.algorithm, Algorithm.sha1);
  expect(code.digits, 6);
  expect(code.period, 30);
  expect(
    code.rawData,
    _expectedStoredTotpRawData(
      issuer: expected.issuer,
      account: expected.account,
      secret: expected.secret,
    ),
  );
}

File _fixture(String name) =>
    File('test/ui/settings/data/import/fixtures/$name');

String _expectedStoredTotpRawData({
  required String issuer,
  required String account,
  required String secret,
}) {
  final encodedIssuer = Uri.encodeComponent(issuer);
  final encodedAccount = Uri.encodeComponent(account);
  final otpUrl =
      'otpauth://totp/$encodedIssuer:$encodedAccount?secret=$secret'
      '&issuer=$encodedIssuer'
      '&algorithm=SHA1'
      '&digits=6'
      '&period=30';
  final code = Code.fromOTPAuthUrl(otpUrl);
  return jsonDecode(code.toOTPAuthUrlFormat()) as String;
}

typedef _ExpectedCode = ({String issuer, String account, String secret});
