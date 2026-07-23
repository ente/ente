import 'package:ente_lock_screen/auth_util.dart';
import 'package:ente_lock_screen/ui/local_authentication_unavailable_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  group("windowsLocalAuthenticationExceptionForError", () {
    test("maps Windows not-enrolled errors to setup guidance", () {
      final exception = windowsLocalAuthenticationExceptionForError(
        PlatformException(
          code: "NotEnrolled",
          message: "No biometrics enrolled on this device.",
        ),
      );

      expect(exception, isNotNull);
      expect(exception!.issue, WindowsLocalAuthIssue.notConfigured);
      expect(exception.userMessage, contains("Windows Hello"));
      expect(exception.userMessage, contains("PIN"));
    });

    test("maps Windows hardware errors to app lock fallback guidance", () {
      final exception = windowsLocalAuthenticationExceptionForError(
        PlatformException(
          code: "NoHardware",
          message: "No biometric hardware found",
        ),
      );

      expect(exception, isNotNull);
      expect(exception!.issue, WindowsLocalAuthIssue.noHardware);
      expect(exception.userMessage, contains("App lock"));
    });

    test("maps LocalAuthException codes", () {
      final exception = windowsLocalAuthenticationExceptionForError(
        const LocalAuthException(
          code: LocalAuthExceptionCode.noBiometricsEnrolled,
        ),
      );

      expect(exception, isNotNull);
      expect(exception!.issue, WindowsLocalAuthIssue.notConfigured);
    });

    test("ignores unrelated platform exceptions", () {
      final exception = windowsLocalAuthenticationExceptionForError(
        PlatformException(code: "UserCanceled"),
      );

      expect(exception, isNull);
    });
  });

  group("isExpectedLocalAuthFailure", () {
    test("treats user-driven cancellations as expected failures", () {
      expect(
        isExpectedLocalAuthFailure(
          const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
        ),
        isTrue,
      );
      expect(
        isExpectedLocalAuthFailure(
          const LocalAuthException(code: LocalAuthExceptionCode.systemCanceled),
        ),
        isTrue,
      );
      expect(
        isExpectedLocalAuthFailure(
          const LocalAuthException(
            code: LocalAuthExceptionCode.userRequestedFallback,
          ),
        ),
        isTrue,
      );
    });

    test("does not hide setup or device errors", () {
      expect(
        isExpectedLocalAuthFailure(
          const LocalAuthException(
            code: LocalAuthExceptionCode.noCredentialsSet,
          ),
        ),
        isFalse,
      );
      expect(
        isExpectedLocalAuthFailure(
          const LocalAuthException(code: LocalAuthExceptionCode.deviceError),
        ),
        isFalse,
      );
    });
  });

  group("localAuthenticationUnavailableExceptionForError", () {
    test("maps missing credentials to setup guidance", () {
      final exception = localAuthenticationUnavailableExceptionForError(
        const LocalAuthException(code: LocalAuthExceptionCode.noCredentialsSet),
      );

      expect(exception, isNotNull);
      expect(exception!.issue, LocalAuthUnavailableIssue.notConfigured);
      expect(exception.userMessage, contains("System authentication"));
      expect(exception.userMessage, contains("PIN/password"));
    });

    test("maps hardware and device errors", () {
      expect(
        localAuthenticationUnavailableExceptionForError(
          const LocalAuthException(
            code: LocalAuthExceptionCode.noBiometricHardware,
          ),
        )!.issue,
        LocalAuthUnavailableIssue.noHardware,
      );
      expect(
        localAuthenticationUnavailableExceptionForError(
          const LocalAuthException(code: LocalAuthExceptionCode.deviceError),
        )!.issue,
        LocalAuthUnavailableIssue.unavailable,
      );
    });

    test("ignores expected user failures", () {
      final exception = localAuthenticationUnavailableExceptionForError(
        const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
      );

      expect(exception, isNull);
    });
  });

  group("shouldShowLinuxSystemAuthSetupGuide", () {
    test("routes Linux setup-required failures to the guide dialog", () {
      expect(
        shouldShowLinuxSystemAuthSetupGuide(
          const LocalAuthenticationUnavailableException(
            issue: LocalAuthUnavailableIssue.linuxSetupRequired,
            code: "noCredentialsSet",
          ),
        ),
        isTrue,
      );
    });

    test("keeps generic local auth failures on toast guidance", () {
      expect(
        shouldShowLinuxSystemAuthSetupGuide(
          const LocalAuthenticationUnavailableException(
            issue: LocalAuthUnavailableIssue.notConfigured,
            code: "noCredentialsSet",
          ),
        ),
        isFalse,
      );
    });
  });
}
