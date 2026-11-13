import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AboutSettingsSection extends StatelessWidget {
  const AboutSettingsSection({super.key, this.onCheckForUpdates});

  final FutureOr<void> Function()? onCheckForUpdates;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final items = [
      SettingsItem(
        title: strings.weAreOpenSource,
        icon: HugeIcons.strokeRoundedGithub,
        showOnlyLoadingState: true,
        onTap: () => _openUrl('https://github.com/ente/ente'),
      ),
      SettingsItem(
        title: strings.blog,
        icon: HugeIcons.strokeRoundedPencilEdit01,
        showOnlyLoadingState: true,
        onTap: () => _openUrl('https://ente.com/blog'),
      ),
      SettingsItem(
        title: strings.privacy,
        icon: HugeIcons.strokeRoundedShield01,
        showOnlyLoadingState: true,
        onTap: () => _openUrl('https://ente.com/privacy'),
      ),
      SettingsItem(
        title: strings.termsOfServicesTitle,
        icon: HugeIcons.strokeRoundedFile01,
        showOnlyLoadingState: true,
        onTap: () => _openUrl('https://ente.com/terms'),
      ),
      if (onCheckForUpdates != null)
        SettingsItem(
          title: strings.checkForUpdates,
          icon: HugeIcons.strokeRoundedDownload04,
          showOnlyLoadingState: true,
          onTap: onCheckForUpdates,
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(height: Spacing.sm),
          items[index],
        ],
      ],
    );
  }

  Future<void> _openUrl(String url) {
    return launchUrlString(
      url,
      mode: PlatformDetector.isMobile()
          ? LaunchMode.inAppBrowserView
          : LaunchMode.externalApplication,
      browserConfiguration: const BrowserConfiguration(showTitle: true),
    );
  }
}
