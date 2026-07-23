import "package:ente_ui/utils/toast_util.dart";
import "package:ente_utils/platform_util.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/services/update_service.dart";
import "package:locker/ui/settings/components/settings_item.dart";
import "package:locker/ui/settings/components/settings_page_scaffold.dart";
import "package:locker/ui/settings/widgets/app_update_dialog.dart";
import "package:url_launcher/url_launcher.dart";

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SettingsPageScaffold(
      title: l10n.about,
      children: [
        SettingsItem(
          title: l10n.weAreOpenSource,
          icon: HugeIcons.strokeRoundedGithub,
          showOnlyLoadingState: true,
          onTap: () => _onOpenSourceTapped(),
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.blog,
          icon: HugeIcons.strokeRoundedPencilEdit01,
          showOnlyLoadingState: true,
          onTap: () => _onBlogTapped(context),
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.privacy,
          icon: HugeIcons.strokeRoundedShield01,
          showOnlyLoadingState: true,
          onTap: () => _onPrivacyTapped(context),
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.termsOfServicesTitle,
          icon: HugeIcons.strokeRoundedFile01,
          showOnlyLoadingState: true,
          onTap: () => _onTermsTapped(context),
        ),
        if (UpdateService.instance.isIndependent()) ...[
          const SizedBox(height: 8),
          SettingsItem(
            title: l10n.checkForUpdates,
            icon: HugeIcons.strokeRoundedDownload04,
            showOnlyLoadingState: true,
            onTap: () => _onCheckForUpdatesTapped(context),
          ),
        ],
      ],
    );
  }

  Future<void> _onOpenSourceTapped() async {
    await launchUrl(Uri.parse("https://github.com/ente/ente"));
  }

  Future<void> _onBlogTapped(BuildContext context) async {
    final l10n = context.l10n;
    await PlatformUtil.openWebView(context, l10n.blog, "https://ente.com/blog");
  }

  Future<void> _onPrivacyTapped(BuildContext context) async {
    final l10n = context.l10n;
    await PlatformUtil.openWebView(
      context,
      l10n.privacy,
      "https://ente.com/privacy",
    );
  }

  Future<void> _onTermsTapped(BuildContext context) async {
    final l10n = context.l10n;
    await PlatformUtil.openWebView(
      context,
      l10n.termsOfServicesTitle,
      "https://ente.com/terms",
    );
  }

  Future<void> _onCheckForUpdatesTapped(BuildContext context) async {
    final l10n = context.l10n;
    final shouldUpdate = await UpdateService.instance.shouldUpdate();
    final latestVersion = UpdateService.instance.getLatestVersionInfo();
    if (!context.mounted) {
      return;
    }
    if (latestVersion == null) {
      showShortToast(context, l10n.unableToCheckForUpdatesRightNow);
      return;
    }
    if (!shouldUpdate) {
      showShortToast(context, l10n.youAreOnTheLatestVersion);
      return;
    }
    await showAppUpdateBottomSheet(context, latestVersionInfo: latestVersion);
  }
}
