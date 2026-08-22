import "dart:io";

import "package:ente_accounts/services/user_service.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/models/settings_search_item.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/services/configuration.dart";
import "package:locker/services/update_service.dart";
import "package:locker/ui/settings/pages/about_page.dart";
import "package:locker/ui/settings/pages/account_settings_page.dart";
import "package:locker/ui/settings/pages/general_settings_page.dart";
import "package:locker/ui/settings/pages/security_settings_page.dart";
import "package:locker/ui/settings/pages/support_page.dart";
import "package:locker/ui/settings/pages/theme_settings_page.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";

class SettingsSearchRegistry {
  static List<SettingsSearchItem> getSearchableItems(BuildContext context) {
    final l10n = context.strings;
    final hasLoggedIn = Configuration.instance.hasConfiguredAccount();

    return [
      if (hasLoggedIn) ...[
        SettingsSearchItem(
          title: l10n.account,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          routeBuilder: (_) => const AccountSettingsPage(),
        ),
        SettingsSearchItem(
          title: l10n.changeEmail,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          routeBuilder: (_) => const AccountSettingsPage(),
        ),
        SettingsSearchItem(
          title: l10n.recoveryKey,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          routeBuilder: (_) => const AccountSettingsPage(),
        ),
        SettingsSearchItem(
          title: l10n.changePassword,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          routeBuilder: (_) => const AccountSettingsPage(),
        ),
        SettingsSearchItem(
          title: l10n.deleteAccount,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          routeBuilder: (_) => const AccountSettingsPage(),
        ),
        SettingsSearchItem(
          title: l10n.security,
          sectionPath: l10n.security,
          icon: HugeIcons.strokeRoundedSecurityCheck,
          routeBuilder: (_) => const SecuritySettingsPage(),
        ),
        SettingsSearchItem(
          title: l10n.twofactor,
          sectionPath: l10n.security,
          icon: HugeIcons.strokeRoundedSmartPhone01,
          routeBuilder: (_) => const SecuritySettingsPage(),
          keywords: const ["2fa", "two factor", "authenticator", "otp"],
        ),
        SettingsSearchItem(
          title: l10n.emailVerificationToggle,
          sectionPath: l10n.security,
          icon: HugeIcons.strokeRoundedSecurityCheck,
          routeBuilder: (_) => const SecuritySettingsPage(),
        ),
        SettingsSearchItem(
          title: l10n.passkey,
          sectionPath: l10n.security,
          icon: HugeIcons.strokeRoundedSecurityCheck,
          routeBuilder: (_) => const SecuritySettingsPage(),
        ),
        SettingsSearchItem(
          title: l10n.appLock,
          sectionPath: l10n.security,
          icon: HugeIcons.strokeRoundedSecurityCheck,
          routeBuilder: (_) => const SecuritySettingsPage(),
        ),
        SettingsSearchItem(
          title: l10n.viewActiveSessions,
          sectionPath: l10n.security,
          icon: HugeIcons.strokeRoundedSecurityCheck,
          routeBuilder: (_) => const SecuritySettingsPage(),
        ),
        if (Platform.isAndroid || kDebugMode)
          SettingsSearchItem(
            title: l10n.appearance,
            sectionPath: l10n.appearance,
            icon: HugeIcons.strokeRoundedSun03,
            routeBuilder: (_) => const ThemeSettingsPage(),
          ),
      ],
      SettingsSearchItem(
        title: l10n.general,
        sectionPath: l10n.general,
        icon: HugeIcons.strokeRoundedSettings01,
        routeBuilder: (_) => const GeneralSettingsPage(),
      ),
      SettingsSearchItem(
        title: l10n.selectLanguage,
        sectionPath: l10n.general,
        icon: HugeIcons.strokeRoundedSettings01,
        routeBuilder: (_) => const GeneralSettingsPage(),
      ),
      SettingsSearchItem(
        title: l10n.helpAndSupport,
        sectionPath: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedHelpCircle,
        routeBuilder: (_) => const SupportPage(),
      ),
      SettingsSearchItem(
        title: l10n.askAQuestion,
        sectionPath: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedHelpCircle,
        routeBuilder: (_) => const SupportPage(),
      ),
      SettingsSearchItem(
        title: l10n.requestAFeature,
        sectionPath: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedHelpCircle,
        routeBuilder: (_) => const SupportPage(),
      ),
      SettingsSearchItem(
        title: l10n.reportAnIssue,
        sectionPath: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedHelpCircle,
        routeBuilder: (_) => const SupportPage(),
      ),
      SettingsSearchItem(
        title: l10n.about,
        sectionPath: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        routeBuilder: (_) => const AboutPage(),
      ),
      SettingsSearchItem(
        title: l10n.weAreOpenSource,
        sectionPath: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        routeBuilder: (_) => const AboutPage(),
      ),
      SettingsSearchItem(
        title: l10n.blog,
        sectionPath: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        routeBuilder: (_) => const AboutPage(),
      ),
      SettingsSearchItem(
        title: l10n.privacy,
        sectionPath: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        routeBuilder: (_) => const AboutPage(),
      ),
      SettingsSearchItem(
        title: l10n.termsOfServicesTitle,
        sectionPath: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        routeBuilder: (_) => const AboutPage(),
      ),
      if (UpdateService.instance.isIndependent())
        SettingsSearchItem(
          title: l10n.checkForUpdates,
          sectionPath: l10n.about,
          icon: HugeIcons.strokeRoundedInformationCircle,
          routeBuilder: (_) => const AboutPage(),
        ),
      if (hasLoggedIn)
        SettingsSearchItem(
          title: l10n.logout,
          sectionPath: l10n.logout,
          icon: HugeIcons.strokeRoundedLogout05,
          onTap: _confirmLogout,
        ),
    ];
  }

  static List<SettingsSearchSuggestion> getSuggestions(
    BuildContext context,
    List<SettingsSearchItem> items,
  ) {
    final l10n = context.strings;
    final titles = Configuration.instance.hasConfiguredAccount()
        ? {l10n.appLock, l10n.appearance, l10n.selectLanguage, l10n.privacy}
        : {l10n.selectLanguage, l10n.privacy};
    return [
      for (final item in items)
        if (titles.contains(item.title))
          SettingsSearchSuggestion(
            title: item.title,
            routeBuilder: item.routeBuilder,
            onTap: item.onTap,
          ),
    ];
  }

  static Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showBottomSheetComponent<bool>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: context.strings.warning,
        message: context.strings.areYouSureYouWantToLogout,
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.strings.yesLogout,
            variant: ButtonComponentVariant.critical,
            shouldSurfaceExecutionStates: false,
            onTap: () => Navigator.of(sheetContext).pop(true),
          ),
        ],
      ),
    );
    if (shouldLogout == true && context.mounted) {
      await UserService.instance.logout(context);
    }
  }
}
