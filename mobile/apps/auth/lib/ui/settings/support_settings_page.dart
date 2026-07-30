import 'package:ente_auth/core/constants.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_item.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/utils/email_util.dart';
import 'package:ente_auth/utils/platform_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportSettingsPage extends StatelessWidget {
  const SupportSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthSettingsPageScaffold(
      title: l10n.support,
      children: [
        AuthSettingsItem(
          title: l10n.faq,
          icon: HugeIcons.strokeRoundedHelpCircle,
          showOnlyLoadingState: true,
          onTap: () => _openFaq(),
        ),
        const SizedBox(height: Spacing.sm),
        AuthSettingsItem(
          title: l10n.suggestFeatures,
          icon: HugeIcons.strokeRoundedIdea01,
          showOnlyLoadingState: true,
          onTap: _suggestFeatures,
        ),
        const SizedBox(height: Spacing.sm),
        AuthSettingsItem(
          title: l10n.reportABug,
          icon: HugeIcons.strokeRoundedBug01,
          showOnlyLoadingState: true,
          onTap: () => sendLogs(context, l10n.reportBug),
          onDoubleTap: () => _shareLogs(context),
        ),
      ],
    );
  }

  Future<void> _openFaq() async {
    try {
      await PlatformUtil.openUrlInBrowser('https://ente.com/help/auth/faq');
    } catch (error, stackTrace) {
      Logger(
        'SupportSettingsPage',
      ).severe('Failed to open FAQ', error, stackTrace);
    }
  }

  Future<void> _suggestFeatures() async {
    final launched = await launchUrl(
      githubFeatureRequestUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      Logger(
        'SupportSettingsPage',
      ).warning('Failed to open feature request discussions');
    }
  }

  Future<void> _shareLogs(BuildContext context) async {
    try {
      final zipFilePath = await getZippedLogsFile(context);
      if (!context.mounted) return;
      await shareLogs(context, 'auth@ente.com', zipFilePath);
    } catch (error, stackTrace) {
      Logger(
        'SupportSettingsPage',
      ).severe('Failed to export logs', error, stackTrace);
    }
  }
}
