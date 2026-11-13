import 'package:ente_auth/ui/settings/data/import/aegis_import.dart';
import 'package:ente_auth/ui/settings/data/import/bitwarden_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports Aegis notes with display metadata', () {
    final code = parseAegisCodes({
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
    }).single;

    expect(code.note, 'Recovery codes are in the safe.');
    expect(code.display.pinned, isTrue);
    expect(code.display.tags, ['Work']);
  });

  test('imports Bitwarden notes with folder tags', () {
    final code = parseBitwardenCodes({
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
    }).single;

    expect(code.note, 'Recovery codes are in the safe.');
    expect(code.display.tags, ['Work']);
  });
}
