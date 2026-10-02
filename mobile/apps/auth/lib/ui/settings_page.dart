import 'dart:io';

import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/onboarding/view/onboarding_page.dart';
import 'package:ente_auth/services/review_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/settings/about_settings_page.dart';
import 'package:ente_auth/ui/settings/account_settings_page.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_navigation.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/ui/settings/data/data_settings_page.dart';
import 'package:ente_auth/ui/settings/data/export_widget.dart';
import 'package:ente_auth/ui/settings/developer_settings_widget.dart';
import 'package:ente_auth/ui/settings/general_settings_page.dart';
import 'package:ente_auth/ui/settings/notification_banner_widget.dart';
import 'package:ente_auth/ui/settings/search/settings_search_registry.dart';
import 'package:ente_auth/ui/settings/security_settings_page.dart';
import 'package:ente_auth/ui/settings/support_settings_page.dart';
import 'package:ente_auth/ui/settings/theme_settings_page.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/buttons/button_widget.dart';
import 'package:ente_ui/components/settings/app_engagement_section.dart';
import 'package:ente_ui/components/settings/more_from_ente_footer.dart';
import 'package:ente_ui/pages/settings_search_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.emailNotifier,
    required this.scaffoldKey,
  });

  final ValueNotifier<String?> emailNotifier;
  final GlobalKey<ScaffoldState> scaffoldKey;

  static const _darkBackupPromptColor = Color(0xFFB868E7);

  @override
  Widget build(BuildContext context) {
    final hasLoggedIn = Configuration.instance.hasConfiguredAccount();
    if (hasLoggedIn) {
      UserService.instance.getUserDetailsV2().ignore();
    }
    return ValueListenableBuilder<String?>(
      valueListenable: emailNotifier,
      builder: (context, email, _) => _buildSettings(
        context,
        hasLoggedIn: hasLoggedIn,
        email: hasLoggedIn ? email : null,
      ),
    );
  }

  Widget _buildSettings(
    BuildContext context, {
    required bool hasLoggedIn,
    required String? email,
  }) {
    final l10n = context.strings;
    final contents = <Widget>[];
    if (hasLoggedIn) {
      contents.add(
        SettingsItem(
          title: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          semanticsIdentifier: 'auth_settings_account',
          onTap: () =>
              pushAuthSettingsPage(context, const AccountSettingsPage()),
        ),
      );
      contents.add(const SizedBox(height: Spacing.sm));
    } else {
      contents.add(
        BannerComponent(
          title: l10n.signInToBackup,
          leadingIcon: HugeIcons.strokeRoundedCloudUpload,
          state: BannerComponentState.informative,
          foregroundColor: Theme.of(context).brightness == Brightness.dark
              ? _darkBackupPromptColor
              : context.componentColors.primaryDark,
          trailingWidget: const Icon(Icons.arrow_forward),
          onTap: () => _showBackupReminder(context),
        ),
      );
      contents.add(const SizedBox(height: Spacing.lg));
    }

    contents.addAll([
      SettingsItem(
        title: l10n.data,
        icon: HugeIcons.strokeRoundedDatabase01,
        semanticsIdentifier: 'auth_settings_data',
        onTap: () => _openDataSettings(context),
      ),
      const SizedBox(height: Spacing.sm),
      SettingsItem(
        title: l10n.security,
        icon: HugeIcons.strokeRoundedSecurityCheck,
        semanticsIdentifier: 'auth_settings_security',
        onTap: () =>
            pushAuthSettingsPage(context, const SecuritySettingsPage()),
      ),
    ]);

    if (Platform.isAndroid ||
        Platform.isWindows ||
        Platform.isLinux ||
        kDebugMode) {
      contents.addAll([
        const SizedBox(height: Spacing.sm),
        SettingsItem(
          title: l10n.theme,
          icon: Theme.of(context).brightness == Brightness.light
              ? HugeIcons.strokeRoundedSun03
              : HugeIcons.strokeRoundedMoon02,
          semanticsIdentifier: 'auth_settings_theme',
          onTap: () => pushAuthSettingsPage(context, const ThemeSettingsPage()),
        ),
      ]);
    }

    contents.addAll([
      const SizedBox(height: Spacing.sm),
      SettingsItem(
        title: l10n.general,
        icon: HugeIcons.strokeRoundedSettings01,
        semanticsIdentifier: 'auth_settings_general',
        onTap: () => pushAuthSettingsPage(context, const GeneralSettingsPage()),
      ),
      const SizedBox(height: Spacing.sm),
      AppEngagementSection(reviewUrl: ReviewService.url),
      const SizedBox(height: Spacing.sm),
      SettingsItem(
        title: l10n.support,
        icon: HugeIcons.strokeRoundedHelpCircle,
        semanticsIdentifier: 'auth_settings_support',
        onTap: () => pushAuthSettingsPage(context, const SupportSettingsPage()),
      ),
      const SizedBox(height: Spacing.sm),
      SettingsItem(
        title: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        semanticsIdentifier: 'auth_settings_about',
        onTap: () => pushAuthSettingsPage(context, const AboutSettingsPage()),
      ),
    ]);

    if (hasLoggedIn) {
      contents.addAll([
        const SizedBox(height: Spacing.sm),
        SettingsItem(
          title: l10n.logout,
          icon: HugeIcons.strokeRoundedLogout05,
          semanticsIdentifier: 'auth_settings_logout',
          isDestructive: true,
          onTap: () => _logout(context),
        ),
      ]);
    }

    contents.addAll([
      const MoreFromEnteFooter(currentApp: ComponentApp.auth),
      const DeveloperSettingsWidget(),
      const NotificationBannerWidget(),
      const SizedBox(height: 60),
    ]);

    return AuthSettingsPageScaffold(
      title: l10n.settings,
      subtitle: email,
      backButton: _closeButton(context),
      actions: [
        IconButtonComponent(
          tooltip: l10n.searchSettings,
          variant: IconButtonComponentVariant.primary,
          shouldSurfaceExecutionStates: false,
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedSearch01,
            size: IconSizes.small,
          ),
          onTap: () => _openSearch(context),
        ),
      ],
      children: contents,
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    final completed = await pushAuthSettingsPage<bool>(
      context,
      Builder(
        builder: (context) {
          final items = SettingsSearchRegistry.getSearchableItems(
            context,
            onSignIn: _showBackupReminder,
            onLogout: _logout,
          );
          return ColoredBox(
            color: context.componentColors.backgroundBase,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width:
                    AuthSettingsPageScaffold.maxContentWidth + 2 * Spacing.lg,
                child: SettingsSearchPage(
                  key: ValueKey(Localizations.localeOf(context)),
                  items: items,
                  suggestions: SettingsSearchRegistry.getSuggestions(
                    context,
                    items,
                  ),
                  onNavigate: (context, routeBuilder) async {
                    final completed = await pushAuthSettingsPage<bool>(
                      context,
                      routeBuilder(context),
                    );
                    if (completed == true && context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
    if (completed == true) {
      scaffoldKey.currentState?.closeDrawer();
    }
  }

  Widget _closeButton(BuildContext context) {
    return Semantics(
      identifier: 'auth_settings_close',
      child: IconButtonComponent(
        tooltip: context.strings.close,
        variant: IconButtonComponentVariant.unfilled,
        shouldSurfaceExecutionStates: false,
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01),
        onTap: () => scaffoldKey.currentState?.closeDrawer(),
      ),
    );
  }

  Future<void> _openDataSettings(BuildContext context) async {
    final completed = await pushAuthSettingsPage<bool>(
      context,
      const DataSettingsPage(),
    );
    if (completed == true) {
      scaffoldKey.currentState?.closeDrawer();
    }
  }

  Future<void> _showBackupReminder(BuildContext context) async {
    final l10n = context.strings;
    final result = await showChoiceActionSheet(
      context,
      title: l10n.note,
      body: l10n.sigInBackupReminder,
      secondButtonLabel: l10n.singIn,
      secondButtonAction: ButtonAction.second,
      firstButtonLabel: l10n.exportCodes,
    );
    if (result == null || !context.mounted) return;
    if (result.action == ButtonAction.first) {
      await handleExportClick(context);
      return;
    }
    if (result.action != ButtonAction.second) return;
    final hasCodes = (await CodeStore.instance.getAllCodes()).any(
      (code) => !code.hasError,
    );
    if (!context.mounted) return;
    if (hasCodes) {
      final authenticated = await LocalAuthenticationService.instance
          .requestLocalAuthentication(context, l10n.authToInitiateSignIn);
      if (!authenticated) return;
    }
    if (context.mounted) {
      await pushAuthSettingsPage(context, const OnboardingPage());
    }
  }

  Future<void> _logout(BuildContext context) {
    final l10n = context.strings;
    return showChoiceActionSheet(
      context,
      title: l10n.logout,
      body: l10n.areYouSureYouWantToLogout,
      firstButtonLabel: l10n.yesLogout,
      secondButtonLabel: l10n.cancel,
      isCritical: true,
      firstButtonOnTap: () => UserService.instance.logout(context),
    );
  }
}
