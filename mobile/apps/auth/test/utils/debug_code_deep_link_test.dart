import 'package:ente_auth/utils/debug_code_deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unwraps a debug add-code link', () {
    const codeUri =
        'otpauth://totp/Example:person@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example';
    final link = Uri(
      scheme: 'enteauth',
      host: 'debug',
      path: '/add-code',
      queryParameters: {'uri': codeUri},
    ).toString();

    final result = parseDebugCodeDeepLink(link);
    expect(result?.action, DebugCodeDeepLinkAction.addCode);
    expect(result?.codeUri, codeUri);
  });

  test('parses debug visual preview links', () {
    const encodedCode =
        'otpauth%3A%2F%2Ftotp%2FExample%3Fsecret%3DJBSWY3DPEHPK3PXP';

    expect(
      parseDebugCodeDeepLink(
        'enteauth://debug/show-qr?uri=$encodedCode',
      )?.action,
      DebugCodeDeepLinkAction.showQr,
    );
    expect(
      parseDebugCodeDeepLink(
        'enteauth://debug/share-code?uri=$encodedCode',
      )?.action,
      DebugCodeDeepLinkAction.shareCode,
    );
    expect(
      parseDebugCodeDeepLink(
        'enteauth://debug/show-icons?uri=$encodedCode',
      )?.action,
      DebugCodeDeepLinkAction.showIcons,
    );
  });

  test('rejects unrelated and non-OTP links', () {
    expect(parseDebugCodeDeepLink('enteauth://search?query=Example'), isNull);
    expect(
      parseDebugCodeDeepLink(
        'enteauth://debug/add-code?uri=https%3A%2F%2Fexample.com',
      ),
      isNull,
    );
  });
}
