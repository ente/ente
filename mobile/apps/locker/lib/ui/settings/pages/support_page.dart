import "package:ente_components/ente_components.dart";
import "package:ente_logging/logging.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_strings/extensions.dart";
import "package:ente_ui/pages/log_file_viewer.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:ente_utils/email_util.dart";
import "package:ente_utils/platform_util.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/core/constants.dart";
import "package:locker/services/feature_flag_service.dart";
import "package:url_launcher/url_launcher_string.dart";

class SupportPage extends StatelessWidget {
  static final _logger = Logger("SupportPage");
  static const _helpUrl = "https://ente.com/help/locker";
  static const _lockerFaqBaseUrl = "https://ente.com/help/locker/faq";
  static const _gettingStartedFaqUrl = "$_lockerFaqBaseUrl/getting-started";
  static const _informationTypesFaqUrl = "$_lockerFaqBaseUrl/information-types";
  static const _organizationFaqUrl = "$_lockerFaqBaseUrl/organization";
  static const _legacyFaqUrl = "$_lockerFaqBaseUrl/legacy";
  static const _securityFaqUrl = "$_lockerFaqBaseUrl/security";
  static const _troubleshootingFaqUrl = "$_lockerFaqBaseUrl/troubleshooting";

  const SupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;

    return SettingsPageScaffold(
      title: l10n.helpAndSupport,
      children: [
        _sectionTitle(context, l10n.getInTouch),
        SettingsItem(
          title: l10n.askAQuestion,
          icon: HugeIcons.strokeRoundedHelpCircle,
          showOnlyLoadingState: true,
          onTap: () => _onAskQuestionTapped(context),
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.requestAFeature,
          icon: HugeIcons.strokeRoundedIdea01,
          showOnlyLoadingState: true,
          onTap: () => _onRequestFeatureTapped(),
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.reportAnIssue,
          icon: HugeIcons.strokeRoundedBug01,
          showOnlyLoadingState: true,
          onTap: () => _onReportIssueTapped(context),
        ),
        if (FeatureFlagService.instance.internalUser || kDebugMode) ...[
          const SizedBox(height: 8),
          SettingsItem(
            title: "(i) ${l10n.viewLogs}",
            icon: HugeIcons.strokeRoundedNote01,
            showOnlyLoadingState: true,
            onTap: () => _viewLogs(context),
          ),
        ],
        SettingsLink(
          label: context.strings.exportLogs,
          onTap: () => _exportLogs(context),
        ),
        const SizedBox(height: 24),
        _sectionTitle(context, l10n.browseHelpPages),
        _buildHelpTopicItem(
          context,
          title: l10n.gettingStarted,
          subText: l10n.gettingStartedDesc,
          icon: HugeIcons.strokeRoundedRocket01,
          faqUrl: _gettingStartedFaqUrl,
        ),
        const SizedBox(height: 8),
        _buildHelpTopicItem(
          context,
          title: l10n.informationTypes,
          subText: l10n.informationTypesDesc,
          icon: HugeIcons.strokeRoundedFile01,
          faqUrl: _informationTypesFaqUrl,
        ),
        const SizedBox(height: 8),
        _buildHelpTopicItem(
          context,
          title: l10n.organization,
          subText: l10n.organizationDesc,
          icon: HugeIcons.strokeRoundedWallet05,
          faqUrl: _organizationFaqUrl,
        ),
        const SizedBox(height: 8),
        _buildHelpTopicItem(
          context,
          title: l10n.legacy,
          subText: l10n.legacyDesc,
          icon: HugeIcons.strokeRoundedFavourite,
          faqUrl: _legacyFaqUrl,
        ),
        const SizedBox(height: 8),
        _buildHelpTopicItem(
          context,
          title: l10n.security,
          subText: l10n.securityDesc,
          icon: HugeIcons.strokeRoundedSecurityCheck,
          faqUrl: _securityFaqUrl,
        ),
        const SizedBox(height: 8),
        _buildHelpTopicItem(
          context,
          title: l10n.troubleshooting,
          subText: l10n.troubleshootingDesc,
          icon: HugeIcons.strokeRoundedWrench01,
          faqUrl: _troubleshootingFaqUrl,
        ),
        SettingsLink(
          label: l10n.viewAllHelpTopics,
          onTap: () => _openHelpPage(context, title: l10n.helpAndSupport),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: Spacing.sm, top: 6, bottom: 6),
      child: Text(title, style: TextStyles.large),
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
      onTap: () => _openHelpPage(context, title: title, url: faqUrl),
    );
  }

  Future<void> _onAskQuestionTapped(BuildContext context) async {
    await sendEmail(context, to: supportEmail);
  }

  Future<void> _onRequestFeatureTapped() async {
    await launchUrlString(
      githubDiscussionsUrl,
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _onReportIssueTapped(BuildContext context) async {
    final l10n = context.strings;
    await sendLogs(
      context,
      "support@ente.com",
      dialogBody: l10n.logsDialogBodyLocker,
    );
  }

  Future<void> _openHelpPage(
    BuildContext context, {
    required String title,
    String url = _helpUrl,
  }) async {
    await PlatformUtil.openWebView(context, title, url);
  }

  Future<void> _viewLogs(BuildContext context) async {
    final logFile = SuperLogging.logFile;
    if (logFile == null) {
      showShortToast(context, context.strings.somethingWentWrong);
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => LogFileViewer(logFile)));
  }

  Future<void> _exportLogs(BuildContext context) async {
    try {
      final zipFilePath = await getZippedLogsFile();
      if (!context.mounted) {
        return;
      }
      await exportLogs(context, zipFilePath);
    } catch (e, s) {
      _logger.severe("Failed to export logs", e, s);
      if (context.mounted) {
        showShortToast(context, context.strings.somethingWentWrong);
      }
    }
  }
}
