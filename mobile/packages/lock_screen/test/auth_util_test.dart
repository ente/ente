import 'package:ente_lock_screen/auth_util.dart';
import 'package:ente_lock_screen/ui/local_authentication_unavailable_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  group("windowsLocalAuthenticationExceptionForError", () {
    final cases = <_WindowsCase>[
      (
        name: "not enrolled",
        error: PlatformException(
          code: "NotEnrolled",
          message: "No biometrics enrolled on this device.",
        ),
        issue: WindowsLocalAuthIssue.notConfigured,
        messages: ["Windows Hello", "PIN"],
      ),
      (
        name: "no hardware",
        error: PlatformException(
          code: "NoHardware",
          message: "No biometric hardware found",
        ),
        issue: WindowsLocalAuthIssue.noHardware,
        messages: ["App lock"],
      ),
      (
        name: "local auth not enrolled",
        error: const LocalAuthException(
          code: LocalAuthExceptionCode.noBiometricsEnrolled,
        ),
        issue: WindowsLocalAuthIssue.notConfigured,
        messages: [],
      ),
      (
        name: "unrelated platform exception",
        error: PlatformException(code: "UserCanceled"),
        issue: null,
        messages: [],
      ),
    ];

    for (final fixture in cases) {
      test(fixture.name, () {
        final exception = windowsLocalAuthenticationExceptionForError(
          fixture.error,
        );
        expect(exception?.issue, fixture.issue);
        for (final message in fixture.messages) {
          expect(exception?.userMessage, contains(message));
        }
      });
    }
  });

  group("isExpectedLocalAuthFailure", () {
    for (final (code, expected) in const [
      (LocalAuthExceptionCode.userCanceled, true),
      (LocalAuthExceptionCode.systemCanceled, true),
      (LocalAuthExceptionCode.userRequestedFallback, true),
      (LocalAuthExceptionCode.noCredentialsSet, false),
      (LocalAuthExceptionCode.deviceError, false),
    ]) {
      test(code.name, () {
        expect(
          isExpectedLocalAuthFailure(LocalAuthException(code: code)),
          expected,
        );
      });
    }
  });

  group("localAuthenticationUnavailableExceptionForError", () {
    const cases = <_UnavailableCase>[
      (
        name: "missing credentials",
        code: LocalAuthExceptionCode.noCredentialsSet,
        issue: LocalAuthUnavailableIssue.notConfigured,
        messages: ["System authentication", "PIN/password"],
      ),
      (
        name: "no hardware",
        code: LocalAuthExceptionCode.noBiometricHardware,
        issue: LocalAuthUnavailableIssue.noHardware,
        messages: [],
      ),
      (
        name: "device error",
        code: LocalAuthExceptionCode.deviceError,
        issue: LocalAuthUnavailableIssue.unavailable,
        messages: [],
      ),
      (
        name: "user cancellation",
        code: LocalAuthExceptionCode.userCanceled,
        issue: null,
        messages: [],
      ),
    ];

    for (final fixture in cases) {
      test(fixture.name, () {
        final exception = localAuthenticationUnavailableExceptionForError(
          LocalAuthException(code: fixture.code),
        );
        expect(exception?.issue, fixture.issue);
        for (final message in fixture.messages) {
          expect(exception?.userMessage, contains(message));
        }
      });
    }
  });

  group("shouldShowLinuxSystemAuthSetupGuide", () {
    for (final (issue, expected) in const [
      (LocalAuthUnavailableIssue.linuxSetupRequired, true),
      (LocalAuthUnavailableIssue.notConfigured, false),
    ]) {
      test(issue.name, () {
        expect(
          shouldShowLinuxSystemAuthSetupGuide(
            LocalAuthenticationUnavailableException(
              issue: issue,
              code: "noCredentialsSet",
            ),
          ),
          expected,
        );
      });
    }
  });
}

typedef _WindowsCase = ({
  String name,
  Object error,
  WindowsLocalAuthIssue? issue,
  List<String> messages,
});

typedef _UnavailableCase = ({
  String name,
  LocalAuthExceptionCode code,
  LocalAuthUnavailableIssue? issue,
  List<String> messages,
});
