import 'dart:io';

import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/onboarding/view/onboarding_page.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/theme/colors.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/models/button_result.dart';
import 'package:ente_auth/ui/components/notification_warning_widget.dart';
import 'package:ente_auth/ui/settings/about_section_widget.dart';
import 'package:ente_auth/ui/settings/account_section_widget.dart';
import 'package:ente_auth/ui/settings/app_version_widget.dart';
import 'package:ente_auth/ui/settings/data/data_section_widget.dart';
import 'package:ente_auth/ui/settings/data/export_widget.dart';
import 'package:ente_auth/ui/settings/developer_settings_widget.dart';
import 'package:ente_auth/ui/settings/general_section_widget.dart';
import 'package:ente_auth/ui/settings/notification_banner_widget.dart';
import 'package:ente_auth/ui/settings/security_section_widget.dart';
import 'package:ente_auth/ui/settings/social_section_widget.dart';
import 'package:ente_auth/ui/settings/support_section_widget.dart';
import 'package:ente_auth/ui/settings/theme_switch_widget.dart';
import 'package:ente_auth/ui/settings/title_bar_widget.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/navigation_util.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  final ValueNotifier<String?> emailNotifier;
  final GlobalKey<ScaffoldState> scaffoldKey;

  SettingsPage({
    super.key,
    required this.emailNotifier,
    required this.scaffoldKey,
  });

  @override
  Widget build(BuildContext context) {
    final hasLoggedIn = Configuration.instance.hasConfiguredAccount();
    if (hasLoggedIn) {
      UserService.instance.getUserDetailsV2().ignore();
    }
    final enteColorScheme = getEnteColorScheme(context);
    return Scaffold(
      body: Container(
        color: enteColorScheme.backdropBase,
        child: _getBody(context, enteColorScheme),
      ),
    );
  }

  Widget _getBody(BuildContext context, EnteColorScheme colorScheme) {
    final hasLoggedIn = Configuration.instance.hasConfiguredAccount();
    final enteTextTheme = getEnteTextTheme(context);
    const sectionSpacing = SizedBox(height: 8);
    final List<Widget> contents = [];
    if (hasLoggedIn) {
      contents.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedBuilder(
              // [AnimatedBuilder] accepts any [Listenable] subtype.
              animation: emailNotifier,
              builder: (BuildContext context, Widget? child) {
                return Text(
                  emailNotifier.value!,
                  style: enteTextTheme.body.copyWith(
                    color: colorScheme.textMuted,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ),
      );
      contents.addAll([
        const SizedBox(height: 12),
        AccountSectionWidget(),
        sectionSpacing,
      ]);
    } else {
      contents.addAll([
        NotificationWidget(
          startIcon: Icons.account_circle_sharp,
          actionIcon: Icons.arrow_forward,
          text: context.l10n.signInToBackup,
          type: NotificationType.notice,
          onTap: () async {
            ButtonResult? result = await showChoiceActionSheet(
              context,
              title: context.l10n.note,
              body: context.l10n.sigInBackupReminder,
              secondButtonLabel: context.l10n.singIn,
              secondButtonAction: ButtonAction.second,
              firstButtonLabel: context.l10n.exportCodes,
            );
            if (result == null) return;
            if (result.action == ButtonAction.first) {
              if (!context.mounted) return;
              await handleExportClick(context);
            } else {
              if (!context.mounted) return;
              if (result.action == ButtonAction.second) {
                bool hasCodes = (await CodeStore.instance.getAllCodes())
                    .where((element) => !element.hasError)
                    .isNotEmpty;
                if (hasCodes) {
                  if (!context.mounted) return;
                  final hasAuthenticated = await LocalAuthenticationService
                      .instance
                      .requestLocalAuthentication(
                        context,
                        context.l10n.authToInitiateSignIn,
                      );
                  if (!hasAuthenticated) {
                    return;
                  }
                }
                if (!context.mounted) return;
                await routeToPage(context, const OnboardingPage());
              }
            }
          },
        ),
        sectionSpacing,
        sectionSpacing,
      ]);
    }
    contents.addAll([
      DataSectionWidget(),
      sectionSpacing,
      const SecuritySectionWidget(),
      sectionSpacing,
    ]);

    if (Platform.isAndroid ||
        Platform.isWindows ||
        Platform.isLinux ||
        kDebugMode) {
      contents.addAll([const ThemeSwitchWidget(), sectionSpacing]);
    }

    contents.addAll([
      const AdvancedSectionWidget(),
      sectionSpacing,
      const SupportSectionWidget(),
      sectionSpacing,
      const SocialSectionWidget(),
      sectionSpacing,
      const AboutSectionWidget(),
      const AppVersionWidget(),
      const DeveloperSettingsWidget(),
      const NotificationBannerWidget(),
      const Padding(padding: EdgeInsets.only(bottom: 60)),
    ]);

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsTitleBarWidget(scaffoldKey: scaffoldKey),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(children: contents),
            ),
          ],
        ),
      ),
    );
  }
}
