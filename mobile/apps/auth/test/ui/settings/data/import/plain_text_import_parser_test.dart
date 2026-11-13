import 'dart:convert';
import 'dart:io';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/plain_text_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  group('plain text import parser', () {
    const secret = 'JBSWY3DPEHPK3PXP';
    const validUri = 'otpauth://totp/Example:valid?secret=$secret';
    const invalidUri = 'otpauth://totp:invalid/Example?secret=$secret';
    final imports = {
      'OTP URLs': '$invalidUri\n$validUri',
      'export JSON': jsonEncode({
        'items': [
          {'rawData': invalidUri},
          {'rawData': validUri},
        ],
      }),
    };

    for (final input in imports.entries) {
      test('logs a safe warning for a skipped entry in ${input.key}', () {
        final records = <LogRecord>[];
        final subscription = Logger.root.onRecord.listen(records.add);
        addTearDown(subscription.cancel);

        final codes = parsePlainTextImport(input.value);

        expect(codes.map((code) => code.rawData), [validUri]);
        final record = records.single;
        expect(record.level, Level.WARNING);
        expect(
          record.message,
          'Skipping malformed import entry (FormatException)',
        );
        expect(record.error, isNull);
        expect(record.stackTrace, isNotNull);
      });
    }

    test('accepts empty content', () {
      expect(parsePlainTextImport(''), isEmpty);
      expect(parsePlainTextImport(' \n\t'), isEmpty);
    });

    test('parses the offline Maestro fixture', () async {
      final content = await File(
        'test/ui/settings/data/import/fixtures/plain_text_import.txt',
      ).readAsString();

      final codes = parsePlainTextImport(content);

      expect(codes, hasLength(2));
      expect(codes[0].type, Type.totp);
      expect(codes[0].issuer, 'GitHub');
      expect(codes[0].account, 'release.bot@github.demo');
      expect(codes[1].type, Type.hotp);
      expect(codes[1].issuer, 'Yubico');
      expect(codes[1].account, 'lab-counter@yubico.demo');
      expect(codes[1].counter, 1);
    });

    test('keeps valid OTP entries when one entry is malformed', () {
      const content = '''
otpauth://totp/Example:valid@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example
not-an-otp-uri
''';

      final codes = parsePlainTextImport(content);

      expect(codes, hasLength(1));
      expect(codes.single.account, 'valid@example.com');
    });

    test('preserves commas inside newline-delimited OTP entries', () {
      const content = '''
otpauth://totp/alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example,%20Inc
otpauth://totp/bob@example.com?secret=GEZDGNBVGY3TQOJQ&issuer=Example
''';

      final codes = parsePlainTextImport(content);

      expect(codes, hasLength(2));
      expect(codes.first.issuer, 'Example, Inc');
      expect(codes.last.account, 'bob@example.com');
    });

    test('parses comma-delimited OTP entries', () {
      const content =
          'otpauth://totp/alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example,'
          'otpauth://totp/bob@example.com?secret=GEZDGNBVGY3TQOJQ&issuer=Example';

      final codes = parsePlainTextImport(content);

      expect(codes, hasLength(2));
    });

    test('preserves display properties from the rich fixture', () async {
      final content = await File(
        'test/ui/settings/data/import/fixtures/rich_display_import.txt',
      ).readAsString();

      final codes = parsePlainTextImport(content);

      expect(codes, hasLength(5));
      expect(codes[0].display.pinned, isTrue);
      expect(codes[0].display.tags, ['Work', 'Admin']);
      expect(
        codes[0].display.note,
        'Primary admin account. Keep recovery contacts current.',
      );
      expect(codes[1].display.trashed, isTrue);
      expect(codes[1].issuer, 'Dropbox');
      expect(codes[1].account, 'archive.bot@dropbox.demo');
      expect(codes[1].display.tags, ['Time capsule', 'Archived']);
      expect(codes[2].digits, 8);
      expect(codes[2].issuer, 'Stripe');
      expect(codes[2].algorithm, Algorithm.sha256);
      expect(codes[2].period, 45);
      expect(codes[2].display.position, 1);
      expect(codes[3].type, Type.steam);
      expect(codes[3].account, 'speedrunner@steam.demo');
      expect(codes[3].display.pinned, isTrue);
      expect(codes[4].type, Type.hotp);
      expect(codes[4].issuer, 'Yubico');
      expect(codes[4].counter, 42);
      expect(codes[4].algorithm, Algorithm.sha512);
    });

    test('rejects JSON without an items list', () {
      expect(
        () => parsePlainTextImport('{"unexpected": []}'),
        throwsFormatException,
      );
    });
  });
}
