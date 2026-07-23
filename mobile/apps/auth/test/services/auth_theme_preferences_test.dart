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
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
  });

  test("returns system when no theme preference exists", () async {
    expect(await AuthThemePreferences.getThemeMode(), ThemeMode.system);
  });

  test("reads Auth theme preference using Flutter ThemeMode index", () async {
    await _setAuthThemeModeIndex(ThemeMode.system.index);
    expect(await AuthThemePreferences.getThemeMode(), ThemeMode.system);

    await _setAuthThemeModeIndex(ThemeMode.light.index);
    expect(await AuthThemePreferences.getThemeMode(), ThemeMode.light);

    await _setAuthThemeModeIndex(ThemeMode.dark.index);
    expect(await AuthThemePreferences.getThemeMode(), ThemeMode.dark);
  });

  test(
    "persists Auth theme preference using Flutter ThemeMode index",
    () async {
      await AuthThemePreferences.setThemeMode(ThemeMode.system);
      expect(await _getAuthThemeModeIndex(), ThemeMode.system.index);

      await AuthThemePreferences.setThemeMode(ThemeMode.light);
      expect(await _getAuthThemeModeIndex(), ThemeMode.light.index);

      await AuthThemePreferences.setThemeMode(ThemeMode.dark);
      expect(await _getAuthThemeModeIndex(), ThemeMode.dark.index);
    },
  );

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
      await _setAsyncAdaptiveThemeModeIndex(0);
      expect(await AuthThemePreferences.getThemeMode(), ThemeMode.light);
      expect(await _getAuthThemeModeIndex(), ThemeMode.light.index);

      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      SharedPreferences.setMockInitialValues({});

      await _setAsyncAdaptiveThemeModeIndex(1);
      expect(await AuthThemePreferences.getThemeMode(), ThemeMode.dark);
      expect(await _getAuthThemeModeIndex(), ThemeMode.dark.index);

      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      SharedPreferences.setMockInitialValues({});

      await _setAsyncAdaptiveThemeModeIndex(2);
      expect(await AuthThemePreferences.getThemeMode(), ThemeMode.system);
      expect(await _getAuthThemeModeIndex(), ThemeMode.system.index);
    },
  );

  test("keeps Auth theme preference when adaptive value resets", () async {
    await AuthThemePreferences.setThemeMode(ThemeMode.light);
    await _setAsyncAdaptiveThemeModeIndex(2);
    await _setLegacyAdaptiveThemeModeIndex(2);

    expect(await AuthThemePreferences.getThemeMode(), ThemeMode.light);
  });
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
