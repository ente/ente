import 'package:ente_auth/services/auth_theme_preferences.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/services/update_service.dart';

// Preference keys that belong to the app rather than to any one account.
//
// They are stored unprefixed, so a logout of the pre-existing (unscoped)
// profile would otherwise delete them along with that account's keys, silently
// resetting the surviving profile's theme, language and backup configuration.
// Configuration.logoutPreservedKeyPrefixes spares everything listed here.
//
// Add a key here whenever a new setting is app wide. Account owned settings
// must NOT be listed: they would then survive a logout and leak into the next
// session.
const kAppWidePreferenceKeys = <String>[
  // Language.
  localePreferenceKey,
  // Appearance. ("theme_mode" is a field inside the adaptive blob below, not a
  // preference key of its own, so it needs no entry here.)
  AuthThemePreferences.authThemeModeKey,
  AuthThemePreferences.adaptiveThemePrefKey,
  // General app preferences.
  PreferenceService.kHasShownCoachMarkKey,
  PreferenceService.kLocalTimeOffsetKey,
  PreferenceService.kShouldShowLargeIconsKey,
  PreferenceService.kShouldHideCodesKey,
  PreferenceService.kShouldAutoFocusOnSearchBar,
  PreferenceService.kShouldMinimizeOnCopy,
  PreferenceService.kShouldMinimizeToTrayOnClose,
  PreferenceService.kCompactMode,
  PreferenceService.kAppInstallTime,
  PreferenceService.kCodeSortKey,
  // Update prompts and desktop window state, neither of which belongs to an
  // account.
  UpdateService.kUpdateAvailableShownTimeKey,
  kIsWindowMaximizedKey,
  // Local backup destination and schedule. The backup password
  // (Configuration.autoBackupPasswordKey) and the last backup day
  // (kLastBackupDayKey) are account scoped and deliberately not here: each
  // vault has to back up on its own, so one vault's backup must not count as
  // the day's backup for the rest.
  kAutoBackupEnabledKey,
  kAutoBackupPathKey,
  kAutoBackupTreeUriKey,
  kAutoBackupIosBookmarkKey,
  kBackupLocationConfiguredKey,
];

const localePreferenceKey = 'locale';

const kIsWindowMaximizedKey = 'is_maximized';

const kAutoBackupEnabledKey = 'isAutoBackupEnabled';
const kAutoBackupPathKey = 'autoBackupPath';
const kAutoBackupTreeUriKey = 'autoBackupTreeUri';
const kAutoBackupIosBookmarkKey = 'autoBackupIosBookmark';
const kBackupLocationConfiguredKey = 'hasConfiguredBackupLocation';
const kLastBackupDayKey = 'lastBackupDay';
