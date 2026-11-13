import "package:photos/service_locator.dart";

bool isChristmasDateRange() {
  final now = DateTime.now();
  return now.month == 12 && now.day >= 24 && now.day <= 26;
}

bool isChristmasPeriod() {
  if (!localSettings.isChristmasBannerEnabled) {
    return false;
  }
  return isChristmasDateRange();
}
