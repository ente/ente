import "dart:async";
import "dart:typed_data";

import "package:ente_components/ente_components.dart";
import "package:ente_crypto/ente_crypto.dart";
import "package:ente_lock_screen/auth_util.dart";
import "package:ente_lock_screen/local_authentication_service.dart";
import "package:ente_lock_screen/ui/lock_screen_options.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:local_auth/local_auth.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/error-reporting/super_logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/user_details_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/user_details.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/account/passkey_service.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/ui/account/request_pwd_verification_page.dart";
import "package:photos/ui/account/sessions_page.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/settings/components/settings_item.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/utils/dialog_util.dart";

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  final _config = Configuration.instance;
  late StreamSubscription<UserDetailsChangedEvent> _userDetailsChangedEvent;
  final Logger _logger = Logger("SecuritySettingsPage");

  @override
  void initState() {
    super.initState();
    _userDetailsChangedEvent = Bus.instance
        .on<UserDetailsChangedEvent>()
        .listen((event) async {
          if (mounted) {
            setState(() {});
          }
        });
    _refreshSecurityDetails().ignore();
  }

  @override
  void dispose() {
    _userDetailsChangedEvent.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showAccountSecurity =
        _config.hasConfiguredAccount() && !isLocalGalleryMode;

    return SettingsPageScaffold(
      title: l10n.security,
      children: [
        if (showAccountSecurity) ...[
          SettingsItem(
            title: l10n.twofactor,
            icon: HugeIcons.strokeRoundedSmartPhone01,
            trailing: ToggleSwitchComponent.async(
              value: () => UserService.instance.hasEnabledTwoFactor(),
              onChanged: () => _onTwoFactorToggle(context),
            ),
          ),
          const SizedBox(height: 8),
          SettingsItem(
            title: l10n.emailVerificationToggle,
            icon: HugeIcons.strokeRoundedMailSecure01,
            trailing: ToggleSwitchComponent.async(
              value: () => UserService.instance.hasEmailMFAEnabled(),
              onChanged: () => _onEmailMFAToggle(context),
            ),
          ),
          const SizedBox(height: 8),
          SettingsItem(
            title: context.l10n.passkey,
            icon: HugeIcons.strokeRoundedFingerAccess,
            onTap: () async => _onPasskeyTap(context),
          ),
          const SizedBox(height: 8),
        ],
        SettingsItem(
          title: l10n.appLock,
          icon: HugeIcons.strokeRoundedSquareLock02,
          onTap: () async => _onAppLockTap(context),
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.crashReporting,
          icon: HugeIcons.strokeRoundedBug02,
          trailing: ToggleSwitchComponent.async(
            value: () => SuperLogging.shouldReportCrashes(),
            onChanged: () async {
              await SuperLogging.setShouldReportCrashes(
                !SuperLogging.shouldReportCrashes(),
              );
              if (mounted) {
                setState(() {});
              }
            },
          ),
        ),
        if (showAccountSecurity) ...[
          const SizedBox(height: 8),
          SettingsItem(
            title: l10n.activeSessions,
            icon: HugeIcons.strokeRoundedComputerPhoneSync,
            showOnlyLoadingState: true,
            onTap: () async => _onActiveSessionsTap(context),
          ),
        ],
      ],
    );
  }

  Future<void> _refreshSecurityDetails() async {
    if (!_config.hasConfiguredAccount() || isLocalGalleryMode) {
      return;
    }
    try {
      await UserService.instance.getUserDetailsV2(memoryCount: false);
      if (mounted) {
        setState(() {});
      }
    } catch (e, s) {
      _logger.warning("failed to refresh security details", e, s);
    }
  }

  Future<void> _onTwoFactorToggle(BuildContext context) async {
    final completer = Completer();
    final hasAuthenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          AppLocalizations.of(context).authToConfigureTwofactorAuthentication,
        );
    final isTwoFactorEnabled = UserService.instance.hasEnabledTwoFactor();
    if (hasAuthenticated) {
      if (isTwoFactorEnabled) {
        await _disableTwoFactor();
        completer.isCompleted ? null : completer.complete();
      } else {
        if (!context.mounted) return;
        await UserService.instance.setupTwoFactor(context, completer);
      }
      return completer.future;
    }
  }

  Future<void> _disableTwoFactor() async {
    final l10n = AppLocalizations.of(context);
    await showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.disableTwofactor,
        message: l10n.confirm2FADisable,
        illustration: Image.asset("assets/warning-grey.png"),
        actions: [
          ButtonComponent(
            label: l10n.yes,
            variant: ButtonComponentVariant.critical,
            onTap: () async {
              await UserService.instance.disableTwoFactor(context);
              if (sheetContext.mounted) {
                Navigator.of(sheetContext).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _onEmailMFAToggle(BuildContext context) async {
    final hasAuthenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          AppLocalizations.of(context).authToChangeEmailVerificationSetting,
        );
    final isEmailMFAEnabled = UserService.instance.hasEmailMFAEnabled();
    if (hasAuthenticated) {
      await _updateEmailMFA(!isEmailMFAEnabled);
    }
  }

  Future<void> _updateEmailMFA(bool isEnabled) async {
    try {
      final UserDetails details = await UserService.instance.getUserDetailsV2(
        memoryCount: false,
      );
      if ((details.profileData?.canDisableEmailMFA ?? false) == false) {
        if (!mounted) return;
        await routeToPage(
          context,
          RequestPasswordVerificationPage(
            onPasswordVerified: (Uint8List keyEncryptionKey) async {
              final Uint8List loginKey = await CryptoUtil.deriveLoginKey(
                keyEncryptionKey,
              );
              await UserService.instance.registerOrUpdateSrp(loginKey);
            },
          ),
        );
      }
      await UserService.instance.updateEmailMFA(isEnabled);
    } catch (e) {
      if (!mounted) return;
      showToast(context, AppLocalizations.of(context).somethingWentWrong);
    }
  }

  Future<void> _onPasskeyTap(BuildContext context) async {
    final hasAuthenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          AppLocalizations.of(context).authToViewPasskey,
        );
    if (hasAuthenticated && mounted && context.mounted) {
      await _handlePasskeyClick(context);
    }
  }

  Future<void> _handlePasskeyClick(BuildContext buildContext) async {
    try {
      final isPassKeyResetEnabled = await PasskeyService.instance
          .isPasskeyRecoveryEnabled();
      if (!mounted || !buildContext.mounted) return;
      if (!isPassKeyResetEnabled) {
        final Uint8List recoveryKey = await UserService.instance
            .getOrCreateRecoveryKey(buildContext);
        final resetKey = CryptoUtil.generateKey();
        final resetKeyBase64 = CryptoUtil.bin2base64(resetKey);
        final encryptionResult = CryptoUtil.encryptSync(resetKey, recoveryKey);
        await PasskeyService.instance.configurePasskeyRecovery(
          resetKeyBase64,
          CryptoUtil.bin2base64(encryptionResult.encryptedData!),
          CryptoUtil.bin2base64(encryptionResult.nonce!),
        );
      }
      if (!mounted || !buildContext.mounted) return;
      PasskeyService.instance.openPasskeyPage(buildContext).ignore();
    } catch (e, s) {
      _logger.severe("failed to open passkey page", e, s);
      if (buildContext.mounted) {
        await showGenericErrorDialog(context: buildContext, error: e);
      }
    }
  }

  Future<void> _onAppLockTap(BuildContext context) async {
    if (await LocalAuthentication().isDeviceSupported()) {
      if (!context.mounted) return;
      final bool result = await requestAuthentication(
        context,
        AppLocalizations.of(context).authToChangeLockscreenSetting,
      );
      if (result) {
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const LockScreenOptions();
            },
          ),
        );
      }
    } else {
      if (!context.mounted) return;
      await showErrorDialog(
        context,
        AppLocalizations.of(context).noSystemLockFound,
        AppLocalizations.of(
          context,
        ).toEnableAppLockPleaseSetupDevicePasscodeOrScreen,
      );
    }
  }

  Future<void> _onActiveSessionsTap(BuildContext context) async {
    final hasAuthenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          AppLocalizations.of(context).authToViewYourActiveSessions,
        );
    if (hasAuthenticated) {
      if (!context.mounted) return;
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const SessionsPage();
            },
          ),
        ),
      );
    }
  }
}
