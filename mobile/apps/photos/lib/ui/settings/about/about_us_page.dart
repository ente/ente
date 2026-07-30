import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/common/web_page.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/settings/app_update_dialog.dart";
import "package:photos/ui/settings/components/settings_item.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/utils/dialog_util.dart";
import "package:url_launcher/url_launcher.dart";

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SettingsPageScaffold(
      title: l10n.about,
      children: [
        SettingsItem(
          title: l10n.weAreOpenSource,
          icon: HugeIcons.strokeRoundedGithub,
          showOnlyLoadingState: true,
          onTap: () async {
            await launchUrl(Uri.parse("https://github.com/ente/ente"));
          },
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.blog,
          icon: HugeIcons.strokeRoundedPencilEdit01,
          showOnlyLoadingState: true,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (BuildContext context) {
                  return WebPage(l10n.blog, "https://ente.com/blog");
                },
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.privacy,
          icon: HugeIcons.strokeRoundedShield01,
          showOnlyLoadingState: true,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (BuildContext context) {
                  return WebPage(l10n.privacy, "https://ente.com/privacy");
                },
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.termsOfServicesTitle,
          icon: HugeIcons.strokeRoundedFile01,
          showOnlyLoadingState: true,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (BuildContext context) {
                  return WebPage(
                    l10n.termsOfServicesTitle,
                    "https://ente.com/terms",
                  );
                },
              ),
            );
          },
        ),
        if (updateService.isIndependent()) ...[
          const SizedBox(height: 8),
          SettingsItem(
            title: l10n.checkForUpdates,
            icon: HugeIcons.strokeRoundedDownload04,
            showOnlyLoadingState: true,
            onTap: () async => _checkForUpdates(context),
          ),
        ],
      ],
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).checking,
    );
    await dialog.show();
    final shouldUpdate = await updateService.shouldUpdate();
    await dialog.hide();
    if (shouldUpdate) {
      if (!context.mounted) return;
      await showDialog(
        useRootNavigator: false,
        context: context,
        builder: (BuildContext context) {
          return AppUpdateDialog(updateService.getLatestVersionInfo());
        },
        barrierColor: Colors.black.withValues(alpha: 0.85),
      );
    } else {
      if (!context.mounted) return;
      showShortToast(
        context,
        AppLocalizations.of(context).youAreOnTheLatestVersion,
      );
    }
  }
}
