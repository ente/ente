import "package:logging/logging.dart";
import "package:photos/service_locator.dart";

extension LoggerExtension on Logger {
  void internalInfo(String message) {
    if (flagService.internalUser) {
      info(message);
    }
  }

  void internalWarning(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (flagService.internalUser) {
      warning(message, error, stackTrace);
    }
  }

  void internalSevere(String message, [Object? error, StackTrace? stackTrace]) {
    if (flagService.internalUser) {
      severe(message, error, stackTrace);
    }
  }
}
