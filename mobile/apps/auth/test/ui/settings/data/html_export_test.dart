import 'dart:convert';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/code_display.dart';
import 'package:ente_auth/ui/settings/data/html_export.dart';
import 'package:ente_auth/ui/settings/data/import/plain_text_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'escapes imported labels and notes after a storage round-trip',
    () async {
      const issuer = 'Issuer </b><script>alert(1)</script>';
      const account = 'alice<svg onload=alert(2)>@example.com';
      const note = 'Keep & safe <img src=x onerror=alert(3)>';
      final uri = Uri(
        scheme: 'otpauth',
        host: 'totp',
        path: '/$issuer:$account',
        queryParameters: {
          'secret': 'JBSWY3DPEHPK3PXP',
          'issuer': issuer,
          'algorithm': 'sha256',
          'codeDisplay': jsonEncode(CodeDisplay(note: note).toJson()),
        },
      ).toString();
      final imported = parsePlainTextImport(uri).single;
      final code = Code.fromOTPAuthUrl(
        jsonDecode(imported.toOTPAuthUrlFormat()) as String,
      );
      expect(code.issuer, issuer);
      expect(code.account, account);
      expect(code.note, note);

      final html = await generateOTPEntryHtml(code);

      expect(
        html,
        contains('Issuer &lt;/b&gt;&lt;script&gt;alert(1)&lt;/script&gt;'),
      );
      expect(html, contains('alice&lt;svg onload=alert(2)&gt;@example.com'));
      expect(
        html,
        contains('Keep &amp; safe &lt;img src=x onerror=alert(3)&gt;'),
      );
      expect(html, isNot(contains('<script>')));
      expect(html, isNot(contains('<svg')));
      expect(html, isNot(contains('<img src=x')));
      expect(html, contains('Secret: <b>JBSWY3DPEHPK3PXP</b>'));
      final qr = await generateQRImageBase64(
        code.rawData.replaceAll('algorithm=sha256', 'algorithm=SHA256'),
      );
      expect(html, contains('src="data:image/png;base64,$qr"'));
    },
  );

  test('preserves plain text and omits an empty note', () async {
    final code = Code.fromOTPAuthUrl(
      Uri(
        scheme: 'otpauth',
        host: 'hotp',
        path: '/Example:橡皮鸭 "quoted" & <literal>',
        queryParameters: {
          'secret': 'JBSWY3DPEHPK3PXP',
          'issuer': 'Example &lt;entity&gt;',
          'counter': '12',
          'digits': '8',
          'algorithm': 'sha512',
        },
      ).toString(),
    );

    final html = await generateOTPEntryHtml(code);

    expect(html, contains('Example &amp;lt;entity&amp;gt;'));
    expect(html, contains('橡皮鸭 "quoted" &amp; &lt;literal&gt;'));
    expect(html, contains('Type: <b>hotp</b>'));
    expect(html, contains('Algorithm: <b>sha512</b>'));
    expect(html, contains('Digits: <b>8</b>'));
    expect(html, isNot(contains('Note:')));
  });

  test('HTML export escapes all code text fields', () async {
    final code = Code(
      'alice<img src=x onerror=alert(1)>@example.com',
      'Issuer <script>alert(2)</script>',
      6,
      30,
      'JBSWY3DPEHPK3PXP<svg onload=alert(3)>',
      Algorithm.sha1,
      Type.totp,
      0,
      'otpauth://totp/Example?secret=JBSWY3DPEHPK3PXP',
      display: CodeDisplay(note: 'Keep & safe <img src=x onerror=alert(4)>'),
    );

    final html = await generateOTPEntryHtml(code);

    expect(
      html,
      contains('alice&lt;img src=x onerror=alert(1)&gt;@example.com'),
    );
    expect(html, contains('Issuer &lt;script&gt;alert(2)&lt;/script&gt;'));
    expect(html, contains('JBSWY3DPEHPK3PXP&lt;svg onload=alert(3)&gt;'));
    expect(
      html,
      contains('Keep &amp; safe &lt;img src=x onerror=alert(4)&gt;'),
    );
    expect(html, contains('Type: <b>totp</b>'));
    expect(html, contains('Algorithm: <b>sha1</b>'));
    expect(html, isNot(contains('<script>alert(2)</script>')));
  });
}
