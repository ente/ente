import 'dart:io';

import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/types/auth_messages_ios.dart';
import 'package:local_auth_darwin/types/auth_messages_macos.dart';
import 'package:logging/logging.dart';

final _logger = Logger("AuthUtil");

enum WindowsLocalAuthIssue {
  notConfigured,
  noHardware,
  unavailable,
  busy,
  disabledByPolicy,
}

enum LocalAuthUnavailableIssue {
  notConfigured,
  noHardware,
  unavailable,
  linuxSetupRequired,
}

class LocalAuthenticationUnavailableException implements Exception {
  const LocalAuthenticationUnavailableException({
    required this.issue,
    required this.code,
    this.description,
    this.originalError,
  });

  final LocalAuthUnavailableIssue issue;
  final String code;
  final String? description;
  final Object? originalError;

  String get userMessage {
    return switch (issue) {
      LocalAuthUnavailableIssue.notConfigured => pendingTranslation(
        "System authentication is not set up. Set it up in your device settings, or switch Ente App lock to PIN/password.",
      ),
      LocalAuthUnavailableIssue.noHardware => pendingTranslation(
        "System authentication is not available on this device. Switch Ente App lock to PIN/password.",
      ),
      LocalAuthUnavailableIssue.unavailable => pendingTranslation(
        "System authentication is not available right now. Try again, or switch Ente App lock to PIN/password.",
      ),
      LocalAuthUnavailableIssue.linuxSetupRequired => pendingTranslation(
        "Linux system authentication needs one-time setup. Install the Ente Auth Polkit policy, or switch Ente App lock to PIN/password.",
      ),
    };
  }

  @override
  String toString() {
    return "LocalAuthenticationUnavailableException($code, $description)";
  }
}

class WindowsLocalAuthenticationException implements Exception {
  const WindowsLocalAuthenticationException({
    required this.issue,
    required this.code,
    this.description,
    this.originalError,
  });

  final WindowsLocalAuthIssue issue;
  final String code;
  final String? description;
  final Object? originalError;

  String get userMessage {
    return switch (issue) {
      WindowsLocalAuthIssue.notConfigured => pendingTranslation(
        "Windows Hello or a Windows PIN is not set up. Set it up in Windows Settings, or switch Ente App lock to PIN/password.",
      ),
      WindowsLocalAuthIssue.noHardware => pendingTranslation(
        "Windows authentication is not available on this device. Switch Ente App lock to PIN/password to use this action.",
      ),
      WindowsLocalAuthIssue.busy => pendingTranslation(
        "Windows authentication is busy. Try again, or switch Ente App lock to PIN/password.",
      ),
      WindowsLocalAuthIssue.disabledByPolicy => pendingTranslation(
        "Windows authentication is disabled by system policy. Switch Ente App lock to PIN/password to use this action.",
      ),
      WindowsLocalAuthIssue.unavailable => pendingTranslation(
        "Windows authentication is not available right now. Set up Windows Hello/PIN or switch Ente App lock to PIN/password.",
      ),
    };
  }

  @override
  String toString() {
    return "WindowsLocalAuthenticationException($code, $description)";
  }
}

WindowsLocalAuthenticationException?
windowsLocalAuthenticationExceptionForError(Object error) {
  if (error is PlatformException) {
    return _windowsLocalAuthenticationExceptionForCode(
      error.code,
      error.message,
      error,
    );
  }
  if (error is LocalAuthException) {
    return _windowsLocalAuthenticationExceptionForLocalAuthException(error);
  }
  return null;
}

bool isExpectedLocalAuthFailure(LocalAuthException error) {
  return switch (error.code) {
    LocalAuthExceptionCode.authInProgress ||
    LocalAuthExceptionCode.userCanceled ||
    LocalAuthExceptionCode.timeout ||
    LocalAuthExceptionCode.systemCanceled ||
    LocalAuthExceptionCode.temporaryLockout ||
    LocalAuthExceptionCode.biometricLockout ||
    LocalAuthExceptionCode.userRequestedFallback => true,
    _ => false,
  };
}

LocalAuthenticationUnavailableException?
localAuthenticationUnavailableExceptionForError(LocalAuthException error) {
  final code = error.code;
  if (Platform.isLinux &&
      code == LocalAuthExceptionCode.noCredentialsSet &&
      (error.description?.contains("Polkit policy") ?? false)) {
    return LocalAuthenticationUnavailableException(
      issue: LocalAuthUnavailableIssue.linuxSetupRequired,
      code: code.name,
      description: error.description,
      originalError: error,
    );
  }
  final issue = switch (code) {
    LocalAuthExceptionCode.noCredentialsSet ||
    LocalAuthExceptionCode.noBiometricsEnrolled =>
      LocalAuthUnavailableIssue.notConfigured,
    LocalAuthExceptionCode.noBiometricHardware =>
      LocalAuthUnavailableIssue.noHardware,
    LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
    LocalAuthExceptionCode.uiUnavailable ||
    LocalAuthExceptionCode.deviceError ||
    LocalAuthExceptionCode.unknownError =>
      LocalAuthUnavailableIssue.unavailable,
    _ => null,
  };
  if (issue == null) {
    return null;
  }
  return LocalAuthenticationUnavailableException(
    issue: issue,
    code: code.name,
    description: error.description,
    originalError: error,
  );
}

WindowsLocalAuthenticationException?
_windowsLocalAuthenticationExceptionForCode(
  String code,
  String? description,
  Object originalError,
) {
  final normalizedCode = code.toLowerCase();
  final normalizedDescription = description?.toLowerCase() ?? "";
  final issue = switch (normalizedCode) {
    final c when c.contains("notenrolled") =>
      WindowsLocalAuthIssue.notConfigured,
    final c when c.contains("nocredentialsset") =>
      WindowsLocalAuthIssue.notConfigured,
    final c when c.contains("nobiometricsenrolled") =>
      WindowsLocalAuthIssue.notConfigured,
    final c when c.contains("nohardware") => WindowsLocalAuthIssue.noHardware,
    final c when c.contains("nobiometrichardware") =>
      WindowsLocalAuthIssue.noHardware,
    final c when c.contains("devicebusy") => WindowsLocalAuthIssue.busy,
    final c when c.contains("authinprogress") => WindowsLocalAuthIssue.busy,
    final c when c.contains("temporarilyunavailable") =>
      WindowsLocalAuthIssue.busy,
    final c when c.contains("disabledbypolicy") =>
      WindowsLocalAuthIssue.disabledByPolicy,
    _ when normalizedDescription.contains("group policy") =>
      WindowsLocalAuthIssue.disabledByPolicy,
    final c when c.contains("notavailable") =>
      WindowsLocalAuthIssue.unavailable,
    final c when c.contains("unavailable") => WindowsLocalAuthIssue.unavailable,
    final c when c.contains("deviceerror") => WindowsLocalAuthIssue.unavailable,
    final c when c.contains("uiunavailable") =>
      WindowsLocalAuthIssue.unavailable,
    final c when c.contains("unknownerror") =>
      WindowsLocalAuthIssue.unavailable,
    _ => null,
  };
  if (issue == null) {
    return null;
  }
  return WindowsLocalAuthenticationException(
    issue: issue,
    code: code,
    description: description,
    originalError: originalError,
  );
}

WindowsLocalAuthenticationException?
_windowsLocalAuthenticationExceptionForLocalAuthException(
  LocalAuthException error,
) {
  final code = error.code;
  if (code == LocalAuthExceptionCode.noCredentialsSet ||
      code == LocalAuthExceptionCode.noBiometricsEnrolled) {
    return WindowsLocalAuthenticationException(
      issue: WindowsLocalAuthIssue.notConfigured,
      code: code.name,
      description: error.description,
      originalError: error,
    );
  }
  if (code == LocalAuthExceptionCode.noBiometricHardware) {
    return WindowsLocalAuthenticationException(
      issue: WindowsLocalAuthIssue.noHardware,
      code: code.name,
      description: error.description,
      originalError: error,
    );
  }
  if (code == LocalAuthExceptionCode.authInProgress ||
      code == LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable) {
    return WindowsLocalAuthenticationException(
      issue: WindowsLocalAuthIssue.busy,
      code: code.name,
      description: error.description,
      originalError: error,
    );
  }
  if (code == LocalAuthExceptionCode.unknownError &&
      (error.description?.toLowerCase().contains("group policy") ?? false)) {
    return WindowsLocalAuthenticationException(
      issue: WindowsLocalAuthIssue.disabledByPolicy,
      code: code.name,
      description: error.description,
      originalError: error,
    );
  }
  if (code == LocalAuthExceptionCode.uiUnavailable ||
      code == LocalAuthExceptionCode.deviceError ||
      code == LocalAuthExceptionCode.unknownError) {
    return WindowsLocalAuthenticationException(
      issue: WindowsLocalAuthIssue.unavailable,
      code: code.name,
      description: error.description,
      originalError: error,
    );
  }
  return null;
}

Future<bool> requestAuthentication(
  BuildContext context,
  String defaultReason, {
  String? title,
  String? macOSReason,
  bool isOpeningApp = false,
  bool isAuthenticatingForInAppChange = false,
}) async {
  final l10n = context.strings;
  final String? savedPin = await LockScreenSettings.instance.getPin();
  final String? savedPassword = await LockScreenSettings.instance.getPassword();
  if (savedPassword != null || savedPin != null) {
    if (!context.mounted) {
      return false;
    }
    return await LocalAuthenticationService.instance
        .requestEnteAuthForLockScreen(
          context,
          savedPin,
          savedPassword,
          isAuthenticatingOnAppLaunch: isOpeningApp,
          isAuthenticatingForInAppChange: isAuthenticatingForInAppChange,
        );
  }
  final localAuth = LocalAuthentication();
  try {
    await localAuth.stopAuthentication();
    await _logLocalAuthState(localAuth);
    final result = await localAuth.authenticate(
      localizedReason: Platform.isMacOS
          ? (macOSReason ?? defaultReason)
          : defaultReason,
      authMessages: [
        AndroidAuthMessages(
          cancelButton: l10n.androidCancelButton,
          signInHint: l10n.androidBiometricHint,
          signInTitle: title ?? l10n.androidSignInTitle,
        ),
        IOSAuthMessages(
          cancelButton: l10n.iOSOkButton,
          localizedFallbackTitle: l10n.enterPassword,
        ),
        MacOSAuthMessages(
          cancelButton: l10n.iOSOkButton,
          localizedFallbackTitle: l10n.enterPassword,
        ),
      ],
    );
    if (Platform.isWindows || Platform.isLinux) {
      _logger.info("System local authentication result: $result");
    }
    return result;
  } on LocalAuthException catch (e, s) {
    final windowsException = Platform.isWindows
        ? windowsLocalAuthenticationExceptionForError(e)
        : null;
    if (windowsException != null) {
      _logger.warning("Windows local authentication failed", e, s);
      throw windowsException;
    }
    final unavailableException =
        localAuthenticationUnavailableExceptionForError(e);
    if (unavailableException != null) {
      _logger.warning("System local authentication unavailable", e, s);
      throw unavailableException;
    }
    if (isExpectedLocalAuthFailure(e)) {
      _logger.fine(
        "Local authentication did not complete: "
        "${e.code.name}, ${e.description}",
      );
      return false;
    }
    _logger.warning("System local authentication failed", e, s);
    rethrow;
  } on PlatformException catch (e, s) {
    final windowsException = Platform.isWindows
        ? windowsLocalAuthenticationExceptionForError(e)
        : null;
    if (windowsException == null) {
      _logger.warning("System local authentication platform error", e, s);
      rethrow;
    }
    _logger.warning("Windows local authentication failed", e, s);
    throw windowsException;
  } catch (e, s) {
    final windowsException = Platform.isWindows
        ? windowsLocalAuthenticationExceptionForError(e)
        : null;
    if (windowsException == null) {
      _logger.warning("Unexpected system local authentication error", e, s);
      rethrow;
    }
    _logger.warning("Windows local authentication failed", e, s);
    throw windowsException;
  }
}

Future<void> _logLocalAuthState(LocalAuthentication localAuth) async {
  if (!Platform.isWindows) {
    return;
  }
  try {
    final isDeviceSupported = await localAuth.isDeviceSupported();
    final canCheckBiometrics = await localAuth.canCheckBiometrics;
    final availableBiometrics = await localAuth.getAvailableBiometrics();
    _logger.info(
      "Windows local authentication state: "
      "isDeviceSupported=$isDeviceSupported, "
      "canCheckBiometrics=$canCheckBiometrics, "
      "availableBiometrics=$availableBiometrics",
    );
  } catch (e, s) {
    _logger.warning("Failed to read local authentication state", e, s);
  }
}
