import 'dart:io';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/services/flagservice.dart';
import 'package:ente_auth/services/review_service.dart';
import 'package:ente_auth/services/update_service.dart';
import 'package:ente_auth/ui/settings/about_settings_page.dart';
import 'package:ente_auth/ui/settings/account_settings_page.dart';
import 'package:ente_auth/ui/settings/data/data_settings_page.dart';
import 'package:ente_auth/ui/settings/data/local_backup_settings_page.dart';
import 'package:ente_auth/ui/settings/general_settings_page.dart';
import 'package:ente_auth/ui/settings/security_settings_page.dart';
import 'package:ente_auth/ui/settings/support_settings_page.dart';
import 'package:ente_auth/ui/settings/theme_settings_page.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/models/settings_search_item.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SettingsSearchRegistry {
  static List<SettingsSearchItem> getSearchableItems(
    BuildContext context, {
    required SettingsSearchAction onSignIn,
    required SettingsSearchAction onLogout,
  }) {
    final l10n = context.strings;
    final hasLoggedIn = Configuration.instance.hasConfiguredAccount();
    return [
      if (hasLoggedIn)
        for (final title in [
          l10n.account,
          l10n.changeEmail,
          l10n.changePassword,
          l10n.recoveryKey,
          l10n.deleteAccount,
        ])
          SettingsSearchItem(
            title: title,
            sectionPath: l10n.account,
            icon: HugeIcons.strokeRoundedUser,
            routeBuilder: (_) => const AccountSettingsPage(),
          )
      else
        SettingsSearchItem(
          title: l10n.signInToBackup,
          sectionPath: l10n.settings,
          icon: HugeIcons.strokeRoundedCloudUpload,
          onTap: onSignIn,
        ),
      for (final title in [
        l10n.data,
        l10n.importCodes,
        l10n.exportCodes,
        l10n.duplicateCodes,
      ])
        SettingsSearchItem(
          title: title,
          sectionPath: l10n.data,
          icon: HugeIcons.strokeRoundedDatabase01,
          routeBuilder: (_) => const DataSettingsPage(),
        ),
      if (FeatureFlagService.isLocalBackupEnabled())
        SettingsSearchItem(
          title: l10n.localBackupSidebarTitle,
          sectionPath: '${l10n.data} > ${l10n.localBackupSidebarTitle}',
          icon: HugeIcons.strokeRoundedHardDrive,
          routeBuilder: (_) => const LocalBackupSettingsPage(),
          keywords: [
            l10n.enableAutomaticBackups,
            l10n.setBackupPassword,
            l10n.updateBackupPassword,
            l10n.setBackupFolder,
            l10n.createBackupNow,
          ],
        ),
      for (final title in [
        l10n.security,
        if (hasLoggedIn) ...[
          l10n.emailVerificationToggle,
          l10n.passkey,
          l10n.viewActiveSessions,
        ],
      ])
        SettingsSearchItem(
          title: title,
          sectionPath: l10n.security,
          icon: HugeIcons.strokeRoundedSecurityCheck,
          routeBuilder: (_) => const SecuritySettingsPage(),
        ),
      SettingsSearchItem(
        title: l10n.appLock,
        sectionPath: l10n.security,
        icon: HugeIcons.strokeRoundedSquareLock02,
        routeBuilder: (_) => const SecuritySettingsPage(),
        keywords: [
          l10n.deviceLock,
          l10n.pinLock,
          l10n.password,
          if (PlatformDetector.isMobile()) ...[l10n.autoLock, l10n.hideContent],
        ],
      ),
      if (Platform.isAndroid ||
          Platform.isWindows ||
          Platform.isLinux ||
          kDebugMode)
        for (final title in [
          l10n.theme,
          l10n.systemTheme,
          l10n.lightTheme,
          l10n.darkTheme,
        ])
          SettingsSearchItem(
            title: title,
            sectionPath: l10n.theme,
            icon: HugeIcons.strokeRoundedSun03,
            routeBuilder: (_) => const ThemeSettingsPage(),
          ),
      for (final title in [
        l10n.general,
        l10n.language,
        if (Platform.isIOS || Platform.isAndroid) l10n.appIcon,
        l10n.showLargeIcons,
        l10n.compactMode,
        l10n.shouldHideCode,
        l10n.focusOnSearchBar,
        if (Platform.isAndroid) l10n.minimizeAppOnCopy,
        if (PlatformDetector.isDesktop()) l10n.minimizeToTrayOnClose,
        if (Platform.isMacOS) l10n.menubarMode,
        l10n.crashAndErrorReporting,
      ])
        SettingsSearchItem(
          title: title,
          sectionPath: l10n.general,
          icon: HugeIcons.strokeRoundedSettings01,
          routeBuilder: (_) => const GeneralSettingsPage(),
        ),
      SettingsSearchItem(
        title: l10n.merchandise,
        sectionPath: l10n.settings,
        icon: HugeIcons.strokeRoundedTShirt,
        onTap: (_) => launchUrlString(
          'https://shop.ente.com',
          mode: LaunchMode.externalApplication,
        ),
      ),
      SettingsSearchItem(
        title: l10n.rateUs,
        sectionPath: l10n.settings,
        icon: HugeIcons.strokeRoundedStar,
        onTap: (_) => launchUrlString(
          ReviewService.url,
          mode: LaunchMode.externalApplication,
        ),
      ),
      for (final title in [
        l10n.support,
        l10n.faq,
        l10n.suggestFeatures,
        l10n.reportABug,
      ])
        SettingsSearchItem(
          title: title,
          sectionPath: l10n.support,
          icon: HugeIcons.strokeRoundedHelpCircle,
          routeBuilder: (_) => const SupportSettingsPage(),
        ),
      for (final title in [
        l10n.about,
        l10n.weAreOpenSource,
        l10n.blog,
        l10n.privacy,
        l10n.termsOfServicesTitle,
        if (UpdateService.instance.supportsInAppUpdates()) l10n.checkForUpdates,
      ])
        SettingsSearchItem(
          title: title,
          sectionPath: l10n.about,
          icon: HugeIcons.strokeRoundedInformationCircle,
          routeBuilder: (_) => const AboutSettingsPage(),
        ),
      if (hasLoggedIn)
        SettingsSearchItem(
          title: l10n.logout,
          sectionPath: l10n.settings,
          icon: HugeIcons.strokeRoundedLogout05,
          onTap: onLogout,
        ),
    ];
  }

  static List<SettingsSearchSuggestion> getSuggestions(
    BuildContext context,
    List<SettingsSearchItem> items,
  ) {
    final l10n = context.strings;
    final titles = {
      l10n.data,
      l10n.security,
      l10n.localBackupSidebarTitle,
      l10n.language,
    };
    return [
      for (final item in items)
        if (titles.contains(item.title))
          SettingsSearchSuggestion(
            title: item.title,
            routeBuilder: item.routeBuilder,
          ),
    ];
  }
}
