import "dart:async";
import "dart:typed_data";

import "package:ente_accounts/models/user_details.dart";
import "package:ente_accounts/pages/request_pwd_verification_page.dart";
import "package:ente_accounts/pages/sessions_page.dart";
import "package:ente_accounts/services/passkey_service.dart";
import "package:ente_accounts/services/user_service.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_crypto_api/ente_crypto_api.dart";
import "package:ente_events/event_bus.dart";
import "package:ente_events/models/user_details_changed_event.dart";
import "package:ente_lock_screen/local_authentication_service.dart";
import "package:ente_lock_screen/lock_screen_settings.dart";
import "package:ente_lock_screen/ui/lock_screen_options.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/services/configuration.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";
import "package:logging/logging.dart";

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  final _config = Configuration.instance;
  final Logger _logger = Logger('SecuritySettingsPage');
  late final StreamSubscription<UserDetailsChangedEvent>
  _userDetailsChangedSubscription;
  late bool _hasLoggedIn;

  @override
  void initState() {
    super.initState();
    _hasLoggedIn = _config.hasConfiguredAccount();
    _userDetailsChangedSubscription = Bus.instance
        .on<UserDetailsChangedEvent>()
        .listen((_) {
          if (mounted) {
            setState(() {});
          }
        });
    if (_hasLoggedIn) {
      unawaited(_refreshSecurityDetails());
    }
  }

  @override
  void dispose() {
    _userDetailsChangedSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;

    return SettingsPageScaffold(
      title: l10n.security,
      children: [
        if (_hasLoggedIn) ...[
          _buildTwoFactorItem(context),
          const SizedBox(height: 8),
          _buildEmailVerificationItem(context),
          const SizedBox(height: 8),
          _buildPasskeyItem(context),
          const SizedBox(height: 8),
        ],
        _buildAppLockItem(context),
        if (_hasLoggedIn) ...[
          const SizedBox(height: 8),
          _buildActiveSessionsItem(context),
        ],
      ],
    );
  }

  Widget _buildTwoFactorItem(BuildContext context) {
    return MergeSemantics(
      child: SettingsItem(
        title: context.strings.twofactor,
        icon: HugeIcons.strokeRoundedSmartPhone01,
        showChevron: false,
        trailing: ToggleSwitchComponent.async(
          value: UserService.instance.hasEnabledTwoFactor,
          onChanged: () => _onTwoFactorToggle(context),
        ),
      ),
    );
  }

  Future<void> _refreshSecurityDetails() async {
    try {
      await UserService.instance.getUserDetailsV2(memoryCount: true);
      if (mounted) {
        setState(() {});
      }
    } catch (e, s) {
      _logger.warning('Failed to refresh security details', e, s);
    }
  }

  Future<void> _onTwoFactorToggle(BuildContext context) async {
    final hasAuthenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.strings.authToConfigureTwofactorAuthentication,
        );
    if (!context.mounted || !hasAuthenticated) {
      return;
    }

    final isTwoFactorEnabled = UserService.instance.hasEnabledTwoFactor();
    if (isTwoFactorEnabled) {
      await _disableTwoFactor(context);
    } else {
      await UserService.instance.setupTwoFactor(context);
    }
  }

  Future<void> _disableTwoFactor(BuildContext context) async {
    final strings = context.strings;
    await showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: strings.disableTwofactor,
        message: strings.confirm2FADisable,
        illustration: Image.asset('assets/warning-grey.png'),
        actions: [
          ButtonComponent(
            label: strings.yes,
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

  Widget _buildEmailVerificationItem(BuildContext context) {
    final l10n = context.strings;

    return SettingsItem(
      title: l10n.emailVerificationToggle,
      icon: HugeIcons.strokeRoundedMailSecure01,
      showChevron: false,
      trailing: ToggleSwitchComponent.async(
        value: () => UserService.instance.hasEmailMFAEnabled(),
        onChanged: () => _onEmailMFAToggle(context),
      ),
    );
  }

  Future<void> _onEmailMFAToggle(BuildContext context) async {
    final hasAuthenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.strings.authToChangeEmailVerificationSetting,
        );
    if (!hasAuthenticated) {
      return;
    }
    final isEmailMFAEnabled = UserService.instance.hasEmailMFAEnabled();
    await _updateEmailMFA(!isEmailMFAEnabled);
  }

  Widget _buildPasskeyItem(BuildContext context) {
    final l10n = context.strings;
    return SettingsItem(
      title: l10n.passkey,
      icon: HugeIcons.strokeRoundedFingerAccess,
      showOnlyLoadingState: true,
      onTap: () => _onPasskeyClick(context),
    );
  }

  Widget _buildActiveSessionsItem(BuildContext context) {
    final l10n = context.strings;
    return SettingsItem(
      title: l10n.viewActiveSessions,
      icon: HugeIcons.strokeRoundedSmartPhone01,
      showOnlyLoadingState: true,
      onTap: () async {
        final hasAuthenticated = await LocalAuthenticationService.instance
            .requestLocalAuthentication(
              context,
              l10n.authToViewYourActiveSessions,
            );
        if (!context.mounted || !hasAuthenticated) {
          return;
        }
        // ignore: unawaited_futures
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return SessionsPage(Configuration.instance);
            },
          ),
        );
      },
    );
  }

  Widget _buildAppLockItem(BuildContext context) {
    final l10n = context.strings;
    return SettingsItem(
      title: l10n.appLock,
      icon: HugeIcons.strokeRoundedSquareLock02,
      showOnlyLoadingState: true,
      onTap: () => _onAppLockTapped(context),
    );
  }

  Future<void> _onAppLockTapped(BuildContext context) async {
    final l10n = context.strings;
    final isDeviceSupported = await LockScreenSettings.instance
        .isDeviceSupported();
    if (!context.mounted) {
      return;
    }
    if (isDeviceSupported) {
      final hasAuthenticated = await LocalAuthenticationService.instance
          .requestLocalAuthentication(
            context,
            l10n.authToChangeLockscreenSetting,
          );
      if (!context.mounted || !hasAuthenticated) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return const LockScreenOptions();
          },
        ),
      );
    } else {
      await showBottomSheetComponent<void>(
        context: context,
        builder: (sheetContext) => BottomSheetComponent(
          title: l10n.noSystemLockFound,
          message: l10n.toEnableAppLockPleaseSetupDevicePasscodeOrScreen,
          illustration: LockerBottomSheetIllustration.warningGrey,
          actions: [
            ButtonComponent(
              label: l10n.ok,
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _onPasskeyClick(BuildContext buildContext) async {
    try {
      final reason = buildContext.strings.authToViewPasskeyGeneric;
      final hasAuthenticated = await LocalAuthenticationService.instance
          .requestLocalAuthentication(
            buildContext,
            reason,
            refocusWindows: false,
          );
      if (!buildContext.mounted || !hasAuthenticated) {
        return;
      }
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
      if (!buildContext.mounted) {
        return;
      }
      await PasskeyService.instance.openPasskeyPage(buildContext);
    } catch (e, s) {
      _logger.severe("failed to open passkey page", e, s);
      if (!buildContext.mounted) {
        return;
      }
      await showErrorBottomSheetComponent<void>(
        context: buildContext,
        message: e.toString(),
        title: buildContext.strings.somethingWentWrong,
      );
    }
  }

  Future<void> _updateEmailMFA(bool isEnabled) async {
    try {
      final UserDetails details = await UserService.instance.getUserDetailsV2(
        memoryCount: false,
      );
      if ((details.profileData?.canDisableEmailMFA ?? false) == false) {
        if (!mounted) {
          return;
        }
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return RequestPasswordVerificationPage(
                Configuration.instance,
                onPasswordVerified: (Uint8List keyEncryptionKey) async {
                  final Uint8List loginKey = await CryptoUtil.deriveLoginKey(
                    keyEncryptionKey,
                  );
                  await UserService.instance.registerOrUpdateSrp(loginKey);
                },
              );
            },
          ),
        );
        if (result != true) {
          return;
        }
      }
      await UserService.instance.updateEmailMFA(isEnabled);
    } catch (e) {
      if (!mounted) {
        return;
      }
      await showErrorBottomSheetComponent<void>(
        context: context,
        message: e.toString(),
        title: context.strings.somethingWentWrong,
      );
    }
  }
}
