import "package:flutter/cupertino.dart";
import "package:logging/logging.dart";
import "package:photos/gateways/users/passkey_gateway.dart";
import "package:photos/service_locator.dart";
import "package:photos/utils/dialog_util.dart";
import 'package:url_launcher/url_launcher_string.dart';

class PasskeyService {
  PasskeyService._privateConstructor();
  static final PasskeyService instance = PasskeyService._privateConstructor();

  PasskeyGateway get _gateway => passkeyGateway;

  Future<String> getAccountsUrl() async {
    final response = await _gateway.getAccountsToken();
    final accountsUrl = response["accountsUrl"] as String;
    final jwtToken = response["accountsToken"] as String;
    return "$accountsUrl/passkeys?token=$jwtToken";
  }

  Future<bool> isPasskeyRecoveryEnabled() async {
    return _gateway.isPasskeyRecoveryEnabled();
  }

  Future<void> configurePasskeyRecovery(
    String secret,
    String userEncryptedSecret,
    String userSecretNonce,
  ) async {
    await _gateway.configurePasskeyRecovery(
      secret: secret,
      userSecretCipher: userEncryptedSecret,
      userSecretNonce: userSecretNonce,
    );
  }

  Future<void> openPasskeyPage(BuildContext context) async {
    try {
      final url = await getAccountsUrl();
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      Logger('PasskeyService').severe("failed to open passkey page", e);
      if (!context.mounted) return;
      showGenericErrorDialog(context: context, error: e).ignore();
    }
  }
}
