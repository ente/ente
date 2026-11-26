import "package:photos/service_locator.dart";

class RewindEdition {
  const RewindEdition._();

  static const int year = 2026;
  static final DateTime availableFrom = DateTime(2026, 12, 5);
  static final DateTime availableUntil = DateTime(2027, 1, 18);

  static bool canPrepare(DateTime now) =>
      flagService.rewind && now.isBefore(availableUntil);

  static bool isAvailable(DateTime now) =>
      canPrepare(now) &&
      (flagService.internalUser || !now.isBefore(availableFrom));

  static bool isPrelaunch(DateTime now) => canPrepare(now) && !isAvailable(now);
}
