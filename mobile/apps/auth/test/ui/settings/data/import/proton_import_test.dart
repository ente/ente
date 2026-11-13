import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/proton_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Proton Authenticator exports', () {
    final codes = parseProtonExport({
      'version': 1,
      'entries': [
        {
          'id': 'totp-id',
          'content': {
            'uri':
                'otpauth://totp/GitHub:alice?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA1&digits=6&period=30',
            'entry_type': 'Totp',
            'name': 'alice',
          },
          'note': 'work account',
        },
        {
          'id': 'steam-id',
          'content': {
            'uri': 'steam://STEAMSECRET',
            'entry_type': 'Steam',
            'name': 'Steam',
          },
          'note': 'gaming',
        },
      ],
    });

    expect(codes, hasLength(2));

    expect(codes[0].type, Type.totp);
    expect(codes[0].issuer, 'GitHub');
    expect(codes[0].account, 'alice');
    expect(codes[0].note, 'work account');

    expect(codes[1].type, Type.steam);
    expect(codes[1].issuer, 'Steam');
    expect(codes[1].secret, 'STEAMSECRET');
    expect(codes[1].note, 'gaming');
  });
}
