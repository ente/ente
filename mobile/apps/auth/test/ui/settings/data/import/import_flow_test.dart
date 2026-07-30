import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildImportOtpUri', () {
    test('normalizes missing and sentinel OTP parameters', () {
      final totpUri = buildImportOtpUri(
        kind: 'totp',
        issuer: 'Example',
        account: 'alice@example.com',
        secret: 'ASKZNWOU6SVYAMVS',
        algorithm: 'SHA1',
        digits: 0,
        period: 0,
      );

      final totpCode = Code.fromOTPAuthUrl(totpUri);
      expect(totpCode.digits, Code.defaultDigits);
      expect(totpCode.period, Code.defaultPeriod);

      final hotpUri = buildImportOtpUri(
        kind: 'hotp',
        issuer: 'Example',
        account: 'alice@example.com',
        secret: 'ASKZNWOU6SVYAMVS',
        algorithm: 'SHA1',
        digits: '0',
        counter: null,
      );

      final hotpCode = Code.fromOTPAuthUrl(hotpUri);
      expect(hotpCode.digits, Code.defaultDigits);
      expect(hotpCode.counter, 0);
    });

    test('rejects unsafe imported OTP parameters', () {
      const entry = {'digits': 11};
      expect(
        () => parseImportOtpCode(
          entry,
          () => buildImportOtpUri(
            kind: 'totp',
            issuer: 'Example',
            account: 'alice@example.com',
            secret: 'ASKZNWOU6SVYAMVS',
            algorithm: 'SHA1',
            digits: 11,
            period: 30,
          ),
        ),
        throwsA(
          isA<ImportEntryParseException>().having(
            (error) => error.entry,
            'entry',
            same(entry),
          ),
        ),
      );
      expect(
        () => buildImportOtpUri(
          kind: 'hotp',
          issuer: 'Example',
          account: 'alice@example.com',
          secret: 'ASKZNWOU6SVYAMVS',
          algorithm: 'SHA1',
          digits: 6,
          counter: -1,
        ),
        throwsFormatException,
      );
    });

    test('keeps compatible nonstandard positive periods', () {
      final uri = buildImportOtpUri(
        kind: 'totp',
        issuer: 'Example',
        account: 'alice@example.com',
        secret: 'ASKZNWOU6SVYAMVS',
        algorithm: 'SHA1',
        digits: 6,
        period: 300,
      );

      expect(Code.fromOTPAuthUrl(uri).period, 300);
    });

    test('formats failed entry details separately from summary error', () {
      const exception = ImportEntryParseException(
        entry: {'issuer': 'Example', 'digits': 11},
        error: FormatException('Invalid OTP digits: 11'),
      );

      expect(exception.toString(), contains('Invalid OTP digits: 11'));
      expect(exception.toString(), isNot(contains('issuer')));
      expect(exception.details, contains('Invalid OTP digits: 11'));
      expect(exception.details, contains('"digits": 11'));
    });

    test('keeps preformatted failed entry details readable', () {
      const exception = ImportEntryParseException(
        entry: '{\n  "digits": 11\n}',
        error: FormatException('Invalid OTP digits: 11'),
      );

      expect(exception.entryText, '{\n  "digits": 11\n}');
    });
  });
}
