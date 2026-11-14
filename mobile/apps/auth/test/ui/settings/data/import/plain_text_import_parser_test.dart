import 'dart:convert';
import 'dart:io';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/plain_text_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import '../../../../helpers/rust.dart';

void main() {
  final skipReason = rustTestSkipReason;
  if (skipReason != null) {
    test('Rust import tests', () {}, skip: skipReason);
    return;
  }
  setUpAll(initializeTestRust);

  group('plain text import parser', () {
    const secret = 'JBSWY3DPEHPK3PXP';
    const validUri = 'otpauth://totp/Example:valid?secret=$secret';
    const invalidUri = 'otpauth://totp:invalid/Example?secret=$secret';
    final imports = {
      'OTP URLs': '$invalidUri\n$invalidUri\n$validUri',
      'export JSON': jsonEncode({
        'items': [
          {'rawData': invalidUri},
          {'rawData': invalidUri},
          {'rawData': validUri},
        ],
      }),
    };

    for (final input in imports.entries) {
      test('logs one warning for skipped entries in ${input.key}', () {
        final records = <LogRecord>[];
        final subscription = Logger.root.onRecord.listen(records.add);
        addTearDown(subscription.cancel);

        final codes = parsePlainTextImport(input.value);

        expect(codes.map((code) => code.rawData), [validUri]);
        final record = records.single;
        expect(record.level, Level.WARNING);
        expect(record.message, 'Skipped 2 malformed plain text import entries');
        expect(record.error, isNull);
        expect(record.stackTrace, isNull);
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

    test('preserves historical raw URI compatibility', () {
      const legacyDisplay = '%7B%22note%22%3A%22legacy%22%7D#suffix';
      const uris = [
        'otpauth://totp/algorithm?secret=$secret&algorithm=SHA224',
        'otpauth://totp/secret?secret=not!',
        'otpauth://totp/digits?secret=$secret&digits=0',
        'otpauth://totp/period?secret=$secret&period=0',
        'otpauth://totp/display?secret=$secret&codeDisplay=$legacyDisplay',
      ];
      const afterMalformed = 'otpauth://totp/after?secret=$secret';

      final codes = parsePlainTextImport(
        [
          ...uris,
          'otpauth://totp/bad?secret=$secret&codeDisplay=not-json}#suffix',
          afterMalformed,
        ].join('\r'),
      );

      expect(codes.map((code) => code.rawData), [...uris, afterMalformed]);
      expect(codes[0].algorithm, Algorithm.sha1);
      expect(codes[1].secret, 'NOT!');
      expect(codes[2].digits, 0);
      expect(codes[3].period, 0);
      expect(codes[4].display.note, 'legacy');
    });

    test('separate rich display overrides legacy embedded metadata', () {
      const uri =
          'otpauth://totp/alice?secret=$secret&codeDisplay='
          '%7B%22note%22%3A%22legacy%22%7D#suffix';
      final codes = parsePlainTextImport(
        jsonEncode({
          'items': [
            {
              'rawData': uri,
              'display': {'note': 'separate'},
            },
          ],
        }),
      );

      expect(codes.single.rawData, uri);
      expect(codes.single.display.note, 'separate');
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
