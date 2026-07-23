import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/onboarding/view/setup_enter_secret_key_page.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new and short manual codes retain the entry limit', () {
    expect(
      SetupEnterSecretKeyPage.manualCodeTextLimitFor(null),
      SetupEnterSecretKeyPage.manualCodeTextLimit,
    );
    expect(
      SetupEnterSecretKeyPage.manualCodeTextLimitFor(_code()),
      SetupEnterSecretKeyPage.manualCodeTextLimit,
    );
  });

  test('legacy manual codes at the limit remain unrestricted', () {
    final boundaryValue = _repeated(
      'a',
      SetupEnterSecretKeyPage.manualCodeTextLimit,
    );

    expect(
      SetupEnterSecretKeyPage.manualCodeTextLimitFor(
        _code(issuer: boundaryValue),
      ),
      isNull,
    );
    expect(
      SetupEnterSecretKeyPage.manualCodeTextLimitFor(
        _code(account: boundaryValue),
      ),
      isNull,
    );
    expect(
      SetupEnterSecretKeyPage.manualCodeTextLimitFor(
        _code(secret: boundaryValue),
      ),
      isNull,
    );
  });

  testWidgets('editing a long legacy value does not truncate it', (
    tester,
  ) async {
    final existingValue = _repeated(
      'a',
      SetupEnterSecretKeyPage.manualCodeTextLimit + 1,
    );
    final updatedValue = '${existingValue}b';
    final controller = TextEditingController(text: existingValue);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(app: ComponentApp.auth),
        home: Scaffold(
          body: TextInputComponent(
            controller: controller,
            maxLength: SetupEnterSecretKeyPage.manualCodeTextLimitFor(
              _code(secret: existingValue),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), updatedValue);

    expect(controller.text, updatedValue);
  });
}

Code _code({
  String issuer = 'Ente',
  String account = 'person@example.com',
  String secret = 'JBSWY3DPEHPK3PXP',
}) {
  return Code.fromAccountAndSecret(Type.totp, account, issuer, secret, null, 6);
}

String _repeated(String value, int count) => List.filled(count, value).join();
