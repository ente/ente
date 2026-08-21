import "dart:convert";

import "package:ente_auth/services/auth_theme_preferences.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart";
import "package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart";

const _authThemeModeKey = "ente_auth_theme_mode";
const _adaptiveThemePrefKey = "adaptive_theme_preferences";

void main() {
  setUp(_resetPreferences);

  test("returns system when no theme preference exists", () async {
    expect(await AuthThemePreferences.getThemeMode(), ThemeMode.system);
  });

  test("prefers Auth theme preference", () async {
    await _setAuthThemeModeIndex(ThemeMode.dark.index);
    await _setAsyncAdaptiveThemeModeIndex(0);
    await _setLegacyAdaptiveThemeModeIndex(0);

    expect(await AuthThemePreferences.getThemeMode(), ThemeMode.dark);
  });

  test("migrates adaptive theme async preference", () async {
    await _setAsyncAdaptiveThemeModeIndex(1);
    await _setLegacyAdaptiveThemeModeIndex(0);

    expect(await AuthThemePreferences.getThemeMode(), ThemeMode.dark);
    expect(await _getAuthThemeModeIndex(), ThemeMode.dark.index);
  });

  test("migrates legacy adaptive theme preference", () async {
    await _setLegacyAdaptiveThemeModeIndex(0);

    expect(await AuthThemePreferences.getThemeMode(), ThemeMode.light);
    expect(await _getAuthThemeModeIndex(), ThemeMode.light.index);
  });

  test(
    "converts adaptive theme indices to Flutter ThemeMode indices",
    () async {
      for (final (adaptiveIndex, mode) in const [
        (0, ThemeMode.light),
        (1, ThemeMode.dark),
        (2, ThemeMode.system),
      ]) {
        _resetPreferences();
        await _setAsyncAdaptiveThemeModeIndex(adaptiveIndex);
        expect(await AuthThemePreferences.getThemeMode(), mode);
        expect(await _getAuthThemeModeIndex(), mode.index);
      }
    },
  );
}

void _resetPreferences() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  SharedPreferences.setMockInitialValues({});
}

Future<void> _setAuthThemeModeIndex(int themeModeIndex) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_authThemeModeKey, themeModeIndex);
}

Future<int?> _getAuthThemeModeIndex() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_authThemeModeKey);
}

Future<void> _setAsyncAdaptiveThemeModeIndex(int themeModeIndex) async {
  final prefs = SharedPreferencesAsync();
  await prefs.setString(
    _adaptiveThemePrefKey,
    _adaptiveThemeJson(themeModeIndex),
  );
}

Future<void> _setLegacyAdaptiveThemeModeIndex(int themeModeIndex) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _adaptiveThemePrefKey,
    _adaptiveThemeJson(themeModeIndex),
  );
}

String _adaptiveThemeJson(int themeModeIndex) {
  return json.encode({"theme_mode": themeModeIndex, "default_theme_mode": 2});
}
