import "package:shared_preferences/shared_preferences.dart";

class LocalSettings {
  LocalSettings._privateConstructor();
  static final LocalSettings instance = LocalSettings._privateConstructor();

  static const _legacySetupBannerDismissedKey =
      "ls.legacy_setup_banner_dismissed";

  late final SharedPreferences _prefs;

  void init(SharedPreferences prefs) {
    _prefs = prefs;
  }

  bool get isLegacySetupBannerDismissed =>
      _prefs.getBool(_legacySetupBannerDismissedKey) ?? false;

  Future<void> setLegacySetupBannerDismissed(bool value) =>
      _prefs.setBool(_legacySetupBannerDismissedKey, value);
}
