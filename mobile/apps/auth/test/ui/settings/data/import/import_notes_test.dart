import 'dart:convert';

import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/rust.dart';

void main() {
  final skipReason = rustTestSkipReason;
  if (skipReason != null) {
    test('Rust import tests', () {}, skip: skipReason);
    return;
  }
  setUpAll(initializeTestRust);

  test('imports Aegis notes with display metadata', () {
    final code = importCode(
      rust
          .parseAegis(
            database: jsonEncode({
              'groups': [
                {'uuid': 'work', 'name': 'Work'},
              ],
              'entries': [
                {
                  'type': 'totp',
                  'name': 'person@example.com',
                  'issuer': 'Example',
                  'favorite': true,
                  'note': 'Recovery codes are in the safe.',
                  'groups': ['work'],
                  'info': {
                    'algo': 'SHA1',
                    'secret': 'JBSWY3DPEHPK3PXP',
                    'period': 30,
                    'digits': 6,
                  },
                },
              ],
            }),
          )
          .codes
          .single,
    );

    expect(code.note, 'Recovery codes are in the safe.');
    expect(code.display.pinned, isTrue);
    expect(code.display.tags, ['Work']);
  });

  test('imports Bitwarden notes with folder tags', () {
    final code = importCode(
      rust
          .parseBitwarden(
            export_: jsonEncode({
              'folders': [
                {'id': 'work', 'name': 'Work'},
              ],
              'items': [
                {
                  'name': 'Example',
                  'folderId': 'work',
                  'notes': 'Recovery codes are in the safe.',
                  'login': {
                    'username': 'person@example.com',
                    'totp':
                        'otpauth://totp/Example:person@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example',
                  },
                },
              ],
            }),
          )
          .codes
          .single,
    );

    expect(code.note, 'Recovery codes are in the safe.');
    expect(code.display.tags, ['Work']);
  });
}
