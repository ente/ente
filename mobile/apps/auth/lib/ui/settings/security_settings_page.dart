import 'dart:typed_data';

import 'package:ente_accounts/models/user_details.dart';
import 'package:ente_accounts/pages/request_pwd_verification_page.dart';
import 'package:ente_accounts/pages/sessions_page.dart';
import 'package:ente_accounts/services/passkey_service.dart';
import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/models/button_result.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_item.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_lock_screen/ui/lock_screen_options.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:logging/logging.dart';

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  final _config = Configuration.instance;
  final _logger = Logger('SecuritySettingsPage');
  late final bool _hasLoggedIn;

  @override
  void initState() {
    super.initState();
    _hasLoggedIn = _config.hasConfiguredAccount();
    if (_hasLoggedIn && UserService.instance.canDisableEmailMFA() == null) {
      UserService.instance.getUserDetailsV2().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthSettingsPageScaffold(
      title: context.l10n.security,
      children: [
        if (_hasLoggedIn) ...[
          AuthSettingsItem(
            title: context.l10n.emailVerificationToggle,
            icon: HugeIcons.strokeRoundedMailSecure01,
            showChevron: false,
            trailing: ToggleSwitchComponent.async(
              value: UserService.instance.hasEmailMFAEnabled,
              onChanged: _toggleEmailMFA,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          AuthSettingsItem(
            title: context.l10n.passkey,
            icon: HugeIcons.strokeRoundedFingerAccess,
            showOnlyLoadingState: true,
            onTap: _openPasskey,
          ),
          const SizedBox(height: Spacing.sm),
          AuthSettingsItem(
            title: context.l10n.viewActiveSessions,
            icon: HugeIcons.strokeRoundedSmartPhone01,
            showOnlyLoadingState: true,
            onTap: _openActiveSessions,
          ),
          const SizedBox(height: Spacing.sm),
        ],
        AuthSettingsItem(
          title: context.l10n.appLock,
          icon: HugeIcons.strokeRoundedSquareLock02,
          showOnlyLoadingState: true,
          onTap: _openAppLock,
        ),
      ],
    );
  }

  Future<void> _toggleEmailMFA() async {
    final hasAuthenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.l10n.authToChangeEmailVerificationSetting,
        );
    if (!hasAuthenticated) return;
    await _updateEmailMFA(!UserService.instance.hasEmailMFAEnabled());
  }

  Future<void> _openPasskey() async {
    try {
      final hasAuthenticated = await LocalAuthenticationService.instance
          .requestLocalAuthentication(
            context,
            context.l10n.authenticateGeneric,
            refocusWindows: false,
          );
      if (!hasAuthenticated) return;
      final isPassKeyResetEnabled = await PasskeyService.instance
          .isPasskeyRecoveryEnabled();
      if (!isPassKeyResetEnabled) {
        final Uint8List recoveryKey = Configuration.instance.getRecoveryKey();
        final resetKey = CryptoUtil.generateKey();
        final resetKeyBase64 = CryptoUtil.bin2base64(resetKey);
        final encryptionResult = CryptoUtil.encryptSync(resetKey, recoveryKey);
        await PasskeyService.instance.configurePasskeyRecovery(
          resetKeyBase64,
          CryptoUtil.bin2base64(encryptionResult.encryptedData!),
          CryptoUtil.bin2base64(encryptionResult.nonce!),
        );
      }
      if (!mounted) return;
      await PasskeyService.instance.openPasskeyPage(context);
    } catch (error, stackTrace) {
      _logger.severe('Failed to open passkey page', error, stackTrace);
      if (mounted) {
        await showGenericErrorDialog(context: context, error: error);
      }
    }
  }

  Future<void> _openActiveSessions() async {
    final hasAuthenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.l10n.authToViewYourActiveSessions,
        );
    if (!hasAuthenticated || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SessionsPage(Configuration.instance)),
    );
  }

  Future<void> _openAppLock() async {
    ButtonResult? result;
    if (_config.hasOptedForOfflineMode() &&
        LockScreenSettings.instance.getOfflineModeWarningStatus()) {
      result = await showChoiceActionSheet(
        context,
        title: context.l10n.warning,
        body: context.l10n.appLockOfflineModeWarning,
        secondButtonLabel: context.l10n.cancel,
        firstButtonLabel: context.l10n.ok,
      );
      if (result?.action != ButtonAction.first) return;
      await LockScreenSettings.instance.setOfflineModeWarningStatus(false);
    }
    if (!mounted) return;
    final hasAuthenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.l10n.authToChangeLockscreenSetting,
        );
    if (!hasAuthenticated || !mounted) return;
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const LockScreenOptions()));
  }

  Future<void> _updateEmailMFA(bool enableEmailMFA) async {
    try {
      final UserDetails details = await UserService.instance.getUserDetailsV2(
        memoryCount: false,
      );
      if (details.profileData?.canDisableEmailMFA == false) {
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => RequestPasswordVerificationPage(
              Configuration.instance,
              onPasswordVerified: (keyEncryptionKey) async {
                final loginKey = await CryptoUtil.deriveLoginKey(
                  keyEncryptionKey,
                );
                await UserService.instance.registerOrUpdateSrp(loginKey);
              },
            ),
          ),
        );
      }
      if (enableEmailMFA) {
        if (!mounted) return;
        await showChoiceActionSheet(
          context,
          title: context.l10n.warning,
          body: context.l10n.emailVerificationEnableWarning,
          isCritical: true,
          firstButtonOnTap: () => UserService.instance.updateEmailMFA(true),
          secondButtonLabel: context.l10n.cancel,
          firstButtonLabel: context.l10n.iUnderStand,
        );
      } else {
        await UserService.instance.updateEmailMFA(false);
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        showToast(context, context.l10n.somethingWentWrongMessage);
      }
    }
  }
}
