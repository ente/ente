import "package:logging/logging.dart";
import "package:photos/service_locator.dart";

extension LoggerExtension on Logger {
  /// Logs an info message only if the user is an internal user.
  ///
  /// This is useful for debug logging that should only be visible to internal
  /// users during development and testing.
  void internalInfo(String message) {
    if (flagService.internalUser) {
      info(message);
    }
  }

  /// Logs a warning message only if the user is an internal user.
  void internalWarning(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (flagService.internalUser) {
      warning(message, error, stackTrace);
    }
  }

  /// Logs a severe message only if the user is an internal user.
  void internalSevere(String message, [Object? error, StackTrace? stackTrace]) {
    if (flagService.internalUser) {
      severe(message, error, stackTrace);
    }
  }
}
