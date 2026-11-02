import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher_string.dart';

class PasskeyService {
  PasskeyService._privateConstructor();
  static final PasskeyService instance = PasskeyService._privateConstructor();

  Future<void> openPasskeyPage(BuildContext context) async {
    try {
      final url = await UserService.instance.passkeyManagementUrl();
      if (!context.mounted) return;
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      Logger('PasskeyService').severe("failed to open passkey page", e);
      if (context.mounted) {
        showGenericErrorDialog(context: context, error: e).ignore();
      }
    }
  }
}
