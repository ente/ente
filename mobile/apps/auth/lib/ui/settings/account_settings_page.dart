import 'dart:async';

import 'package:ente_account_deletion/account_deletion.dart';
import 'package:ente_accounts/pages/change_email_dialog.dart';
import 'package:ente_accounts/pages/password_entry_page.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/components/recovery_key_sheet.dart';
import 'package:ente_auth/ui/home_page.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_item.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthSettingsPageScaffold(
      title: l10n.account,
      children: [
        AuthSettingsItem(
          title: l10n.changeEmail,
          icon: HugeIcons.strokeRoundedMailEdit01,
          onTap: () => _changeEmail(context),
        ),
        const SizedBox(height: Spacing.sm),
        AuthSettingsItem(
          title: l10n.changePassword,
          icon: HugeIcons.strokeRoundedLockPassword,
          onTap: () => _changePassword(context),
        ),
        const SizedBox(height: Spacing.sm),
        AuthSettingsItem(
          title: l10n.recoveryKey,
          icon: HugeIcons.strokeRoundedKey01,
          onTap: () => _showRecoveryKey(context),
        ),
        const SizedBox(height: Spacing.sm),
        AuthSettingsItem(
          title: l10n.deleteAccount,
          icon: HugeIcons.strokeRoundedDelete02,
          isDestructive: true,
          onTap: () => _deleteAccount(context),
        ),
      ],
    );
  }

  Future<void> _changeEmail(BuildContext context) async {
    final authenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.l10n.authToChangeYourEmail,
        );
    if (authenticated && context.mounted) {
      await showChangeEmailDialog(context);
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final authenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.l10n.authToChangeYourPassword,
        );
    if (!authenticated || !context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PasswordEntryPage(
          Configuration.instance,
          PasswordEntryMode.update,
          const HomePage(),
        ),
      ),
    );
  }

  Future<void> _showRecoveryKey(BuildContext context) async {
    final authenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.l10n.authToViewYourRecoveryKey,
        );
    if (!authenticated || !context.mounted) return;
    try {
      final recoveryKey = CryptoUtil.bin2hex(
        Configuration.instance.getRecoveryKey(),
      );
      await showRecoveryKeySheet(context, recoveryKey: recoveryKey);
    } catch (error) {
      if (!context.mounted) return;
      unawaited(showGenericErrorDialog(context: context, error: error));
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final authenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.l10n.authToInitiateAccountDeletion,
        );
    if (!authenticated || !context.mounted) return;
    final deleted = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const DeleteAccountPage()));
    if (deleted == true && context.mounted) {
      unawaited(
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
      );
    }
  }
}
