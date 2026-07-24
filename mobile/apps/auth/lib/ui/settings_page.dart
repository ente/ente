import 'dart:io';

import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/onboarding/view/onboarding_page.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/settings/about_settings_page.dart';
import 'package:ente_auth/ui/settings/account_settings_page.dart';
import 'package:ente_auth/ui/settings/app_version_widget.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_item.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_navigation.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/ui/settings/data/data_settings_page.dart';
import 'package:ente_auth/ui/settings/data/export_widget.dart';
import 'package:ente_auth/ui/settings/developer_settings_widget.dart';
import 'package:ente_auth/ui/settings/general_settings_page.dart';
import 'package:ente_auth/ui/settings/more_from_ente_section.dart';
import 'package:ente_auth/ui/settings/notification_banner_widget.dart';
import 'package:ente_auth/ui/settings/security_settings_page.dart';
import 'package:ente_auth/ui/settings/social_icons_row.dart';
import 'package:ente_auth/ui/settings/support_settings_page.dart';
import 'package:ente_auth/ui/settings/theme_settings_page.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.emailNotifier,
    required this.scaffoldKey,
  });

  final ValueNotifier<String?> emailNotifier;
  final GlobalKey<ScaffoldState> scaffoldKey;

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
    final l10n = context.l10n;
    final contents = <Widget>[];
    if (hasLoggedIn) {
      contents.add(
        AuthSettingsItem(
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
          onTap: () => _showBackupReminder(context),
        ),
      );
      contents.add(const SizedBox(height: Spacing.lg));
    }

    contents.addAll([
      AuthSettingsItem(
        title: l10n.data,
        icon: HugeIcons.strokeRoundedDatabase01,
        semanticsIdentifier: 'auth_settings_data',
        onTap: () => _openDataSettings(context),
      ),
      const SizedBox(height: Spacing.sm),
      AuthSettingsItem(
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
        AuthSettingsItem(
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
      AuthSettingsItem(
        title: l10n.general,
        icon: HugeIcons.strokeRoundedSettings01,
        semanticsIdentifier: 'auth_settings_general',
        onTap: () => pushAuthSettingsPage(context, const GeneralSettingsPage()),
      ),
      const SizedBox(height: Spacing.sm),
      AuthSettingsItem(
        title: l10n.support,
        icon: HugeIcons.strokeRoundedHelpCircle,
        semanticsIdentifier: 'auth_settings_support',
        onTap: () => pushAuthSettingsPage(context, const SupportSettingsPage()),
      ),
      const SizedBox(height: Spacing.sm),
      AuthSettingsItem(
        title: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        semanticsIdentifier: 'auth_settings_about',
        onTap: () => pushAuthSettingsPage(context, const AboutSettingsPage()),
      ),
    ]);

    if (hasLoggedIn) {
      contents.addAll([
        const SizedBox(height: Spacing.sm),
        AuthSettingsItem(
          title: l10n.logout,
          icon: HugeIcons.strokeRoundedLogout05,
          semanticsIdentifier: 'auth_settings_logout',
          isDestructive: true,
          onTap: () => _logout(context),
        ),
      ]);
    }

    final showMoreFromEnte = Platform.isIOS || Platform.isAndroid;
    if (showMoreFromEnte) {
      contents.addAll([
        const SizedBox(height: 40),
        MoreFromEnteSection(
          currentApp: ComponentApp.auth,
          moreFromLabel: context.strings.moreFrom,
          onAppTap: (app) {
            launchUrlString(
              moreFromEnteUri(
                sourceApp: ComponentApp.auth,
                destinationApp: app,
              ).toString(),
              mode: LaunchMode.externalApplication,
            ).ignore();
          },
        ),
      ]);
    }

    contents.addAll([
      SizedBox(height: showMoreFromEnte ? 40 : Spacing.xxl),
      const SocialIconsRow(),
      const SizedBox(height: Spacing.md),
      const AppVersionWidget(),
      const SizedBox(height: Spacing.xxl),
      const DeveloperSettingsWidget(),
      const NotificationBannerWidget(),
      const SizedBox(height: 60),
    ]);

    return AuthSettingsPageScaffold(
      title: l10n.settings,
      subtitle: email,
      backButton: _closeButton(context),
      children: contents,
    );
  }

  Widget _closeButton(BuildContext context) {
    return Semantics(
      identifier: 'auth_settings_close',
      child: IconButtonComponent(
        tooltip: context.l10n.close,
        variant: IconButtonComponentVariant.unfilled,
        shouldSurfaceExecutionStates: false,
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01),
        onTap: () => scaffoldKey.currentState?.closeDrawer(),
      ),
    );
  }

  Future<void> _openDataSettings(BuildContext context) async {
    final completed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const DataSettingsPage()));
    if (completed == true) {
      scaffoldKey.currentState?.closeDrawer();
    }
  }

  Future<void> _showBackupReminder(BuildContext context) async {
    final l10n = context.l10n;
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
    final l10n = context.l10n;
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
