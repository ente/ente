import 'dart:async';

import 'package:ente_account_deletion/account_deletion.dart';
import 'package:ente_accounts/pages/change_email_dialog.dart';
import 'package:ente_accounts/pages/password_entry_page.dart';
import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/components/captioned_text_widget.dart';
import 'package:ente_auth/ui/components/expandable_menu_item_widget.dart';
import 'package:ente_auth/ui/components/menu_item_widget.dart';
import 'package:ente_auth/ui/components/recovery_key_sheet.dart';
import 'package:ente_auth/ui/home_page.dart';
import 'package:ente_auth/ui/settings/common_settings.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:flutter/material.dart';

class AccountSectionWidget extends StatelessWidget {
  AccountSectionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ExpandableMenuItemWidget(
      title: l10n.account,
      selectionOptionsWidget: _getSectionOptions(context),
      leadingIcon: Icons.account_circle_outlined,
    );
  }

  Column _getSectionOptions(BuildContext context) {
    final l10n = context.l10n;
    List<Widget> children = [];
    children.addAll([
      sectionOptionSpacing,
      MenuItemWidget(
        captionedTextWidget: CaptionedTextWidget(title: l10n.changeEmail),
        pressedColor: getEnteColorScheme(context).fillFaint,
        trailingIcon: Icons.chevron_right_outlined,
        trailingIconIsMuted: true,
        onTap: () async {
          final hasAuthenticated = await LocalAuthenticationService.instance
              .requestLocalAuthentication(context, l10n.authToChangeYourEmail);
          if (hasAuthenticated) {
            if (!context.mounted) return;
            // ignore: unawaited_futures
            showChangeEmailDialog(context);
          }
        },
      ),
      sectionOptionSpacing,
      MenuItemWidget(
        captionedTextWidget: CaptionedTextWidget(title: l10n.changePassword),
        pressedColor: getEnteColorScheme(context).fillFaint,
        trailingIcon: Icons.chevron_right_outlined,
        trailingIconIsMuted: true,
        onTap: () async {
          final hasAuthenticated = await LocalAuthenticationService.instance
              .requestLocalAuthentication(
                context,
                l10n.authToChangeYourPassword,
              );
          if (hasAuthenticated) {
            if (!context.mounted) return;
            // ignore: unawaited_futures
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (BuildContext context) {
                  return PasswordEntryPage(
                    Configuration.instance,
                    PasswordEntryMode.update,
                    const HomePage(),
                  );
                },
              ),
            );
          }
        },
      ),
      sectionOptionSpacing,
      MenuItemWidget(
        captionedTextWidget: CaptionedTextWidget(title: l10n.recoveryKey),
        pressedColor: getEnteColorScheme(context).fillFaint,
        trailingIcon: Icons.chevron_right_outlined,
        trailingIconIsMuted: true,
        onTap: () async {
          final hasAuthenticated = await LocalAuthenticationService.instance
              .requestLocalAuthentication(
                context,
                l10n.authToViewYourRecoveryKey,
              );
          if (hasAuthenticated) {
            if (!context.mounted) return;
            String recoveryKey;
            try {
              recoveryKey = CryptoUtil.bin2hex(
                Configuration.instance.getRecoveryKey(),
              );
            } catch (e) {
              // ignore: unawaited_futures
              showGenericErrorDialog(context: context, error: e);
              return;
            }
            // ignore: unawaited_futures
            showRecoveryKeySheet(context, recoveryKey: recoveryKey);
          }
        },
      ),
      sectionOptionSpacing,
      MenuItemWidget(
        captionedTextWidget: CaptionedTextWidget(title: context.l10n.logout),
        pressedColor: getEnteColorScheme(context).fillFaint,
        trailingIcon: Icons.chevron_right_outlined,
        trailingIconIsMuted: true,
        onTap: () async {
          _onLogoutTapped(context);
        },
      ),
      sectionOptionSpacing,
      MenuItemWidget(
        captionedTextWidget: CaptionedTextWidget(
          title: context.l10n.deleteAccount,
        ),
        pressedColor: getEnteColorScheme(context).fillFaint,
        trailingIcon: Icons.chevron_right_outlined,
        trailingIconIsMuted: true,
        onTap: () async {
          final hasAuthenticated = await LocalAuthenticationService.instance
              .requestLocalAuthentication(
                context,
                l10n.authToInitiateAccountDeletion,
              );
          if (!context.mounted || !hasAuthenticated) {
            return;
          }
          final deleted = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (BuildContext context) {
                return const DeleteAccountPage();
              },
            ),
          );
          if (deleted == true && context.mounted) {
            unawaited(
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/', (route) => false),
            );
          }
        },
      ),
      sectionOptionSpacing,
    ]);
    return Column(children: children);
  }

  void _onLogoutTapped(BuildContext context) {
    showChoiceActionSheet(
      context,
      title: context.l10n.areYouSureYouWantToLogout,
      firstButtonLabel: context.l10n.yesLogout,
      isCritical: true,
      firstButtonOnTap: () async {
        await UserService.instance.logout(context);
      },
    );
  }
}
