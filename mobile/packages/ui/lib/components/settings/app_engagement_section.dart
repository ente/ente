import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AppEngagementSection extends StatelessWidget {
  const AppEngagementSection({super.key, required this.reviewUrl});

  final String reviewUrl;

  static Future<void> _launchMerchandise() {
    return _openExternalUrl('https://shop.ente.com');
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return MenuGroupComponent(
      items: [
        SettingsItem(
          title: strings.merchandise,
          icon: HugeIcons.strokeRoundedTShirt,
          showOnlyLoadingState: true,
          onTap: _launchMerchandise,
        ),
        SettingsItem(
          title: strings.rateUs,
          icon: HugeIcons.strokeRoundedStar,
          showOnlyLoadingState: true,
          onTap: () => _openExternalUrl(reviewUrl),
        ),
      ],
    );
  }

  static Future<void> _openExternalUrl(String url) {
    return launchUrlString(url, mode: LaunchMode.externalApplication);
  }
}
