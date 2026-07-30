import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/services/update_service.dart';
import 'package:ente_auth/ui/settings/app_update_dialog.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_item.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/platform_util.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthSettingsPageScaffold(
      title: l10n.about,
      children: [
        AuthSettingsItem(
          title: l10n.weAreOpenSource,
          icon: HugeIcons.strokeRoundedGithub,
          showOnlyLoadingState: true,
          onTap: () =>
              PlatformUtil.openUrlInBrowser('https://github.com/ente/ente'),
        ),
        const SizedBox(height: Spacing.sm),
        AuthSettingsItem(
          title: l10n.blog,
          icon: HugeIcons.strokeRoundedPencilEdit01,
          showOnlyLoadingState: true,
          onTap: () => PlatformUtil.openUrlInBrowser('https://ente.com/blog'),
        ),
        const SizedBox(height: Spacing.sm),
        AuthSettingsItem(
          title: l10n.merchandise,
          icon: HugeIcons.strokeRoundedShoppingBag01,
          showOnlyLoadingState: true,
          onTap: () => PlatformUtil.openUrlInBrowser('https://shop.ente.com'),
        ),
        const SizedBox(height: Spacing.sm),
        AuthSettingsItem(
          title: l10n.privacy,
          icon: HugeIcons.strokeRoundedShield01,
          showOnlyLoadingState: true,
          onTap: () =>
              PlatformUtil.openUrlInBrowser('https://ente.com/privacy'),
        ),
        const SizedBox(height: Spacing.sm),
        AuthSettingsItem(
          title: l10n.termsOfServicesTitle,
          icon: HugeIcons.strokeRoundedFile01,
          showOnlyLoadingState: true,
          onTap: () => PlatformUtil.openUrlInBrowser('https://ente.com/terms'),
        ),
        if (UpdateService.instance.supportsInAppUpdates()) ...[
          const SizedBox(height: Spacing.sm),
          AuthSettingsItem(
            title: l10n.checkForUpdates,
            icon: HugeIcons.strokeRoundedDownload04,
            showOnlyLoadingState: true,
            onTap: () => _checkForUpdates(context),
          ),
        ],
      ],
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final dialog = createProgressDialog(context, context.l10n.checking);
    await dialog.show();
    final shouldUpdate = await UpdateService.instance.shouldUpdate();
    await dialog.hide();
    if (!context.mounted) return;
    if (shouldUpdate) {
      await showDialog<void>(
        context: context,
        builder: (_) =>
            AppUpdateDialog(UpdateService.instance.getLatestVersionInfo()),
        barrierColor: Colors.black.withValues(alpha: 0.85),
      );
      return;
    }
    showShortToast(context, context.l10n.youAreOnTheLatestVersion);
  }
}
