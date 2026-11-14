import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('import errors', () {
    test('keeps failed entry details out of the summary error', () {
      const exception = ImportEntryParseException(
        entry: {'issuer': 'Example', 'digits': 11},
        error: FormatException('Invalid OTP digits: 11'),
      );

      expect(exception.toString(), contains('Invalid OTP digits: 11'));
      expect(exception.toString(), isNot(contains('issuer')));
      expect(exception.details, contains('Invalid OTP digits: 11'));
      expect(exception.details, contains('"digits": 11'));
    });

    test('keeps Rust entry details out of the summary error', () async {
      const secret = 'SENSITIVE-OTP-SECRET';

      try {
        await runRustImportAsync<void>(
          () async => throw const rust.ImportError.invalid(
            message: 'Invalid OTP secret',
            entry: '{"secret":"$secret"}',
          ),
        );
        fail('expected an import error');
      } on ImportEntryParseException catch (error) {
        expect(error.toString(), isNot(contains(secret)));
        expect(error.entryText, contains(secret));
      }
    });

    test('preserves password-required Rust errors', () async {
      await expectLater(
        runRustImportAsync<void>(
          () async => throw const rust.ImportError.passwordRequired(),
        ),
        throwsA(isA<rust.ImportError_PasswordRequired>()),
      );
    });
  });
}
