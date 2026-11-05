import "package:photos/service_locator.dart";

class RewindEdition {
  const RewindEdition._();

  static const int year = 2026;
  static final DateTime availableFrom = DateTime(2026, 12, 5);
  static final DateTime availableUntil = DateTime(2027, 1, 18);

  static bool isAvailable(DateTime now) {
    if (!flagService.rewind || !now.isBefore(availableUntil)) {
      return false;
    }
    return flagService.internalUser || !now.isBefore(availableFrom);
  }
}
