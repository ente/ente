import "dart:convert";

import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

class AuthThemePreferences {
  AuthThemePreferences._();

  static const _authThemeModeKey = "ente_auth_theme_mode";
  static const _adaptiveThemePrefKey = "adaptive_theme_preferences";
  static const _themeModeKey = "theme_mode";

  static Future<ThemeMode> getThemeMode() async {
    final authThemeMode = await _getAuthThemeMode();
    if (authThemeMode != null) {
      return authThemeMode;
    }

    final migratedThemeMode = await _getMigratedThemeMode();
    if (migratedThemeMode != null) {
      await _setAuthThemeMode(migratedThemeMode);
      return migratedThemeMode;
    }

    return ThemeMode.system;
  }

  static Future<void> setThemeMode(ThemeMode themeMode) =>
      _setAuthThemeMode(themeMode);

  static Future<ThemeMode?> _getAuthThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return _authThemeModeFromIndex(prefs.getInt(_authThemeModeKey));
  }

  static Future<void> _setAuthThemeMode(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    // Auth owns this key, so persist Flutter's ThemeMode.index directly.
    await prefs.setInt(_authThemeModeKey, themeMode.index);
  }

  static Future<ThemeMode?> _getMigratedThemeMode() async {
    // AdaptiveTheme can live in either the newer async backend or the legacy
    // cached SharedPreferences backend depending on platform/plugin history.
    final prefs = SharedPreferencesAsync();
    return _parseAdaptiveThemeMode(
          await prefs.getString(_adaptiveThemePrefKey),
        ) ??
        await _getLegacyAdaptiveThemeMode();
  }

  static Future<ThemeMode?> _getLegacyAdaptiveThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseAdaptiveThemeMode(prefs.getString(_adaptiveThemePrefKey));
  }

  static ThemeMode? _parseAdaptiveThemeMode(String? themeDataString) {
    if (themeDataString == null || themeDataString.isEmpty) {
      return null;
    }

    try {
      final decoded = json.decode(themeDataString);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final themeModeIndex = decoded[_themeModeKey];
      return _adaptiveThemeModeFromIndex(themeModeIndex);
    } on FormatException {
      return null;
    }
  }

  static ThemeMode? _authThemeModeFromIndex(Object? themeModeIndex) {
    if (themeModeIndex is! int ||
        themeModeIndex < 0 ||
        themeModeIndex >= ThemeMode.values.length) {
      return null;
    }
    return ThemeMode.values[themeModeIndex];
  }

  static ThemeMode? _adaptiveThemeModeFromIndex(Object? themeModeIndex) {
    // AdaptiveTheme persisted its own enum order: light=0, dark=1, system=2.
    // Keep this separate from Flutter's ThemeMode.index used by Auth's key.
    switch (themeModeIndex) {
      case 0:
        return ThemeMode.light;
      case 1:
        return ThemeMode.dark;
      case 2:
        return ThemeMode.system;
      default:
        return null;
    }
  }
}
