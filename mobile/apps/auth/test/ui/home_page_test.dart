import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/home_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('newly added code focus search prefers issuer', () {
    final code = Code.fromOTPAuthUrl(
      'otpauth://totp/person@example.com?secret=ASKZNWOU6SVYAMVS&issuer=GitHub',
    );

    expect(addedCodeFocusSearchQuery(code), 'GitHub');
  });

  test('newly added code focus search falls back to account', () {
    final code = Code.fromOTPAuthUrl(
      'otpauth://totp/person@example.com?secret=ASKZNWOU6SVYAMVS',
    );

    expect(addedCodeFocusSearchQuery(code), 'person@example.com');
  });
}
