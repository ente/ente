import 'package:ente_network/network.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher_string.dart';

class PasskeyService {
  PasskeyService._privateConstructor();
  static final PasskeyService instance = PasskeyService._privateConstructor();

  final _enteDio = Network.instance.enteDio;

  Future<String> getAccountsUrl() async {
    final response = await _enteDio.get("/users/accounts-token");
    final accountsUrl = response.data!["accountsUrl"] as String;
    final jwtToken = response.data!["accountsToken"] as String;
    return "$accountsUrl/passkeys?token=$jwtToken";
  }

  Future<bool> isPasskeyRecoveryEnabled() async {
    final response = await _enteDio.get("/users/two-factor/recovery-status");
    return response.data!["isPasskeyRecoveryEnabled"] as bool;
  }

  Future<void> configurePasskeyRecovery(
    String secret,
    String userEncryptedSecret,
    String userSecretNonce,
  ) async {
    await _enteDio.post(
      "/users/two-factor/passkeys/configure-recovery",
      data: {
        "secret": secret,
        "userSecretCipher": userEncryptedSecret,
        "userSecretNonce": userSecretNonce,
      },
    );
  }

  Future<void> openPasskeyPage(BuildContext context) async {
    try {
      final url = await getAccountsUrl();
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      Logger('PasskeyService').severe("failed to open passkey page", e);
      if (context.mounted) {
        showGenericErrorDialog(context: context, error: e).ignore();
      }
    }
  }
}
