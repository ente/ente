import "package:ente_components/ente_components.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/error-reporting/super_logging.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/common/web_page.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/settings/components/settings_item.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/ui/settings/support/report_issue_page.dart";
import "package:photos/ui/tools/debug/log_file_viewer.dart";
import "package:photos/utils/email_util.dart";
import "package:url_launcher/url_launcher_string.dart";

class HelpSupportPage extends StatelessWidget {
  static final _logger = Logger("HelpSupportPage");
  static const _helpUrl = "https://ente.com/help";
  static const _photosFaqBaseUrl = "https://ente.com/help/photos/faq";
  static const _searchAndDiscoveryFaqUrl =
      "$_photosFaqBaseUrl/search-and-discovery";
  static const _backupAndSyncFaqUrl = "$_photosFaqBaseUrl/backup-and-sync";
  static const _sharingAndCollaborationFaqUrl =
      "$_photosFaqBaseUrl/sharing-and-collaboration";
  static const _storageAndPlansFaqUrl = "$_photosFaqBaseUrl/storage-and-plans";
  static const _troubleshootingFaqUrl = "$_photosFaqBaseUrl/troubleshooting";

  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SettingsPageScaffold(
      title: l10n.helpAndSupport,
      children: [
        _sectionTitle(context, l10n.getInTouch),
        SettingsItem(
          title: l10n.askAQuestion,
          icon: HugeIcons.strokeRoundedHelpCircle,
          showOnlyLoadingState: true,
          onTap: () async {
            await openEmailComposer(context, to: supportEmail);
          },
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.requestAFeature,
          icon: HugeIcons.strokeRoundedIdea01,
          showOnlyLoadingState: true,
          onTap: () async {
            await launchUrlString(
              githubDiscussionsUrl,
              mode: LaunchMode.externalApplication,
            );
          },
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.reportAnIssue,
          icon: HugeIcons.strokeRoundedBug01,
          showOnlyLoadingState: true,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const ReportIssuePage()),
            );
          },
        ),
        if (flagService.internalUser || kDebugMode) ...[
          const SizedBox(height: 8),
          SettingsItem(
            title: "(i) ${l10n.viewLogs}",
            icon: HugeIcons.strokeRoundedNote01,
            showOnlyLoadingState: true,
            onTap: () async {
              await _viewLogs(context);
            },
          ),
        ],
        _SupportLink(
          label: l10n.exportLogs,
          onTap: () async {
            await _exportLogs(context);
          },
        ),
        const SizedBox(height: 24),
        _sectionTitle(context, l10n.browseHelpPages),
        _buildHelpTopicItem(
          context,
          title: l10n.searchAndDiscovery,
          subText: l10n.searchAndDiscoveryDesc,
          icon: HugeIcons.strokeRoundedSearch01,
          faqUrl: _searchAndDiscoveryFaqUrl,
        ),
        const SizedBox(height: 8),
        _buildHelpTopicItem(
          context,
          title: l10n.backupAndSync,
          subText: l10n.backupAndSyncDesc,
          icon: HugeIcons.strokeRoundedCloudUpload,
          faqUrl: _backupAndSyncFaqUrl,
        ),
        const SizedBox(height: 8),
        _buildHelpTopicItem(
          context,
          title: l10n.sharingAndCollaboration,
          subText: l10n.sharingAndCollaborationDesc,
          icon: HugeIcons.strokeRoundedShare04,
          faqUrl: _sharingAndCollaborationFaqUrl,
        ),
        const SizedBox(height: 8),
        _buildHelpTopicItem(
          context,
          title: l10n.storageAndPlans,
          subText: l10n.storageAndPlansDesc,
          icon: HugeIcons.strokeRoundedDatabase,
          faqUrl: _storageAndPlansFaqUrl,
        ),
        const SizedBox(height: 8),
        _buildHelpTopicItem(
          context,
          title: l10n.troubleshooting,
          subText: l10n.troubleshootingDesc,
          icon: HugeIcons.strokeRoundedWrench01,
          faqUrl: _troubleshootingFaqUrl,
        ),
        _SupportLink(
          label: l10n.viewAllHelpTopics,
          onTap: () async {
            await _openHelpPage(context, title: l10n.helpAndSupport);
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final colors = context.componentColors;
    return Padding(
      padding: const EdgeInsets.only(left: Spacing.sm, top: 6, bottom: 6),
      child: Text(
        title,
        style: TextStyles.large.copyWith(color: colors.textBase),
      ),
    );
  }

  Widget _buildHelpTopicItem(
    BuildContext context, {
    required String title,
    required String subText,
    required List<List<dynamic>> icon,
    required String faqUrl,
  }) {
    return SettingsItem(
      title: title,
      subtitle: subText,
      subtitleMaxLines: 2,
      icon: icon,
      showOnlyLoadingState: true,
      onTap: () async {
        await _openHelpPage(context, title: title, url: faqUrl);
      },
    );
  }

  Future<void> _openHelpPage(
    BuildContext context, {
    required String title,
    String url = _helpUrl,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return WebPage(title, url);
        },
      ),
    );
  }

  Future<void> _viewLogs(BuildContext context) async {
    final logFile = SuperLogging.logFile;
    if (logFile == null) {
      showShortToast(context, AppLocalizations.of(context).somethingWentWrong);
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => LogFileViewer(logFile)));
  }

  Future<void> _exportLogs(BuildContext context) async {
    try {
      final zipFilePath = await getZippedLogsFile(context);
      if (!context.mounted) return;
      await exportLogs(context, zipFilePath);
    } catch (e, s) {
      _logger.severe("Failed to export logs", e, s);
      if (context.mounted) {
        showShortToast(
          context,
          AppLocalizations.of(context).somethingWentWrong,
        );
      }
    }
  }
}

class _SupportLink extends StatelessWidget {
  final String label;
  final Future<void> Function() onTap;

  const _SupportLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyles.bodyBold.copyWith(color: colors.primary),
            ),
            const SizedBox(width: 4),
            HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              color: colors.primary,
              size: 16,
              strokeWidth: 1.6,
            ),
          ],
        ),
      ),
    );
  }
}
