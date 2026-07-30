import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/otp_auth_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OTP Auth import parser', () {
    for (final version in ['1.0', '1.1']) {
      test('decrypts backup version $version', () async {
        final codes = parseOtpAuthExport(
          await _fixture('backup-$version.otpauthdb'),
          password: 'abc123',
        );

        expect(codes, hasLength(2));
        _expectCode(
          codes.first,
          type: Type.totp,
          issuer: 'Example TOTP',
          account: 'alice@example.com',
          secret: 'MJQWG23VOAWXI33UOAWXGZLDOJSXI',
        );
        _expectCode(
          codes.last,
          type: Type.hotp,
          issuer: 'Example HOTP',
          account: 'bob@example.com',
          secret: 'MJQWG23VOAWWQ33UOAWXGZLDOJSXI',
        );
        expect(codes.last.counter, 7);
      });
    }

    test('decrypts single-account version 1.1', () async {
      final codes = parseOtpAuthExport(
        await _fixture('account-1.1.otpauth'),
        password: 'abc123',
      );

      expect(codes, hasLength(1));
      _expectCode(
        codes.single,
        type: Type.totp,
        issuer: 'Legacy Account',
        account: 'legacy@example.com',
        secret: 'ONUW4Z3MMUWWYZLHMFRXSLLTMVRXEZLU',
      );
    });

    test('decrypts single-account version 1.2', () async {
      final codes = parseOtpAuthExport(
        await _fixture('account-1.2.otpauth'),
        password: 'abc123',
      );

      expect(codes, hasLength(1));
      _expectCode(
        codes.single,
        type: Type.totp,
        issuer: 'Modern Account',
        account: 'modern@example.com',
        secret: 'ONUW4Z3MMUWW233EMVZG4LLTMVRXEZLU',
      );
    });

    for (final version in ['1.0', '1.1']) {
      test('rejects an incorrect password for backup version $version', () {
        expect(
          () async => parseOtpAuthExport(
            await _fixture('backup-$version.otpauthdb'),
            password: 'wrong-password',
          ),
          throwsA(isA<IncorrectOtpAuthPasswordException>()),
        );
      });
    }
  });
}

void _expectCode(
  Code code, {
  required Type type,
  required String issuer,
  required String account,
  required String secret,
}) {
  expect(code.type, type);
  expect(code.issuer, issuer);
  expect(code.account, account);
  expect(code.secret, secret);
  expect(code.algorithm, Algorithm.sha1);
  expect(code.digits, Code.defaultDigits);
  expect(code.period, Code.defaultPeriod);
}

Future<Uint8List> _fixture(String name) async {
  final encoded = await File(
    'test/ui/settings/data/import/fixtures/$name.b64',
  ).readAsString();
  return base64Decode(encoded.replaceAll(RegExp(r'\s'), ''));
}
