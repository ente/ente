import 'dart:io';

import 'package:ente_lock_screen/auth_util.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_lock_screen/ui/app_lock.dart';
import 'package:ente_lock_screen/ui/local_authentication_unavailable_dialog.dart';
import 'package:ente_lock_screen/ui/lock_screen_password.dart';
import 'package:ente_lock_screen/ui/lock_screen_pin.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:ente_utils/platform_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_linux/local_auth_linux.dart';
import 'package:logging/logging.dart';

class LocalAuthenticationService {
  LocalAuthenticationService._privateConstructor();
  static final LocalAuthenticationService instance =
      LocalAuthenticationService._privateConstructor();
  final logger = Logger((LocalAuthenticationService).toString());
  int lastAuthTime = 0;

  Future<bool> requestLocalAuthentication(
    BuildContext context,
    String infoMessage, {
    String? title,
    bool refocusWindows = true,
    bool useDebugAuthCache = true,
  }) async {
    if (kDebugMode && useDebugAuthCache) {
      // if last auth time is less than 60 seconds, don't ask for auth again
      if (lastAuthTime != 0 &&
          DateTime.now().millisecondsSinceEpoch - lastAuthTime < 60000) {
        return true;
      }
    }
    if (await isLocalAuthSupportedOnDevice() ||
        LockScreenSettings.instance.getIsAppLockSet()) {
      final appLock = AppLock.of(context);
      appLock?.setEnabled(false);
      bool result = false;
      WindowsLocalAuthenticationException? windowsLocalAuthException;
      LocalAuthenticationUnavailableException? localAuthUnavailableException;
      try {
        result = await requestAuthentication(
          context,
          infoMessage,
          title: title,
          macOSReason: context.strings.unlock,
          isAuthenticatingForInAppChange: true,
        );
      } on WindowsLocalAuthenticationException catch (e, s) {
        windowsLocalAuthException = e;
        logger.warning("Windows local authentication failed", e, s);
      } on LocalAuthenticationUnavailableException catch (e, s) {
        localAuthUnavailableException = e;
        logger.warning("System local authentication unavailable", e, s);
      } finally {
        appLock?.setEnabled(
          await LockScreenSettings.instance.shouldShowLockScreen(),
        );
        if (refocusWindows) {
          await PlatformUtil.refocusWindows();
        }
      }
      if (windowsLocalAuthException != null) {
        if (context.mounted) {
          showToast(context, windowsLocalAuthException.userMessage);
        }
        return false;
      }
      if (localAuthUnavailableException != null) {
        if (context.mounted) {
          await showLocalAuthenticationUnavailableMessage(
            context,
            localAuthUnavailableException,
          );
        }
        return false;
      }
      if (!result) {
        showToast(context, infoMessage);
        return false;
      } else {
        if (useDebugAuthCache) {
          lastAuthTime = DateTime.now().millisecondsSinceEpoch;
        }
        return true;
      }
    }
    return true;
  }

  Future<bool> requestEnteAuthForLockScreen(
    BuildContext context,
    String? savedPin,
    String? savedPassword, {
    bool isAuthenticatingOnAppLaunch = false,
    bool isAuthenticatingForInAppChange = false,
  }) async {
    if (savedPassword != null) {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return LockScreenPassword(
              isChangingLockScreenSettings: true,
              isAuthenticatingForInAppChange: isAuthenticatingForInAppChange,
              isAuthenticatingOnAppLaunch: isAuthenticatingOnAppLaunch,
              authPass: savedPassword,
            );
          },
        ),
      );
      if (result == true) {
        return true;
      }
    }
    if (savedPin != null) {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return LockScreenPin(
              isChangingLockScreenSettings: true,
              isAuthenticatingForInAppChange: isAuthenticatingForInAppChange,
              isAuthenticatingOnAppLaunch: isAuthenticatingOnAppLaunch,
              authPin: savedPin,
            );
          },
        ),
      );
      if (result == true) {
        return true;
      }
    }
    return false;
  }

  Future<bool> requestLocalAuthForLockScreen(
    BuildContext context,
    bool shouldEnableLockScreen,
    String infoMessage,
    String errorDialogContent, [
    String errorDialogTitle = "",
  ]) async {
    if (await isLocalAuthSupportedOnDevice()) {
      bool didEnableLockScreen = false;
      AppLock.of(context)!.disable();
      try {
        final result = await requestAuthentication(
          context,
          infoMessage,
          macOSReason: context.strings.unlock,
        );
        if (result) {
          AppLock.of(context)!.setEnabled(shouldEnableLockScreen);
          await LockScreenSettings.instance.setSystemLockScreen(
            shouldEnableLockScreen,
          );
          didEnableLockScreen = true;
          return true;
        }
      } on WindowsLocalAuthenticationException catch (e, s) {
        logger.warning("Windows local authentication failed", e, s);
        if (context.mounted) {
          showToast(context, e.userMessage);
        }
      } on LocalAuthenticationUnavailableException catch (e, s) {
        logger.warning("System local authentication unavailable", e, s);
        if (context.mounted) {
          await showLocalAuthenticationUnavailableMessage(context, e);
        }
      } finally {
        if (!didEnableLockScreen) {
          AppLock.of(context)!.setEnabled(
            await LockScreenSettings.instance.shouldShowLockScreen(),
          );
        }
      }
    } else {
      // ignore: unawaited_futures
      showErrorDialog(context, errorDialogTitle, errorDialogContent);
    }
    return false;
  }

  Future<bool> isLocalAuthSupportedOnDevice() async {
    try {
      if (Platform.isLinux) {
        final status = await getLinuxLocalAuthSetupStatus();
        logger.info(
          "Linux local authentication support: "
          "polkitAvailable=${status?.polkitAvailable}, "
          "policyInstalled=${status?.policyInstalled}, "
          "isFlatpak=${status?.isFlatpak}, "
          "error=${status?.errorMessage}",
        );
        return status?.polkitAvailable == true &&
            status?.policyInstalled == true;
      }
      if (Platform.isWindows) {
        final localAuth = LocalAuthentication();
        final isSupported = await localAuth.isDeviceSupported();
        logger.info(
          "Windows local authentication support: "
          "isDeviceSupported=$isSupported",
        );
        return isSupported;
      }
      return await LocalAuthentication().isDeviceSupported();
    } on MissingPluginException {
      logger.warning("Local authentication plugin is not available");
      return false;
    } on PlatformException catch (e, s) {
      if (!Platform.isWindows) {
        rethrow;
      }
      logger.warning("Failed to check Windows local authentication", e, s);
      return false;
    }
  }

  Future<LinuxLocalAuthSetupStatus?> getLinuxLocalAuthSetupStatus() async {
    if (!Platform.isLinux) {
      return null;
    }
    try {
      return await LocalAuthLinux().getSetupStatus();
    } on MissingPluginException {
      logger.warning("Linux local authentication plugin is not available");
      return null;
    } on PlatformException catch (e, s) {
      logger.warning("Failed to check Linux local authentication setup", e, s);
      return null;
    }
  }
}
