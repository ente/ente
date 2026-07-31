import 'dart:io';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/services/update_service.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SocialIconsRow extends StatelessWidget {
  const SocialIconsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final rateDetails = UpdateService.instance.getRateDetails();
    final links = <_SocialLink>[
      if (PlatformDetector.isMobile())
        _SocialLink(
          label: context.l10n.rateUsOnStore(rateDetails.item1),
          identifier: 'auth_settings_rate',
          icon: HugeIcons.strokeRoundedStar,
          url: rateDetails.item2,
        ),
      const _SocialLink(
        label: 'Discord',
        identifier: 'auth_settings_social_discord',
        icon: HugeIcons.strokeRoundedDiscord,
        url: 'https://ente.com/discord',
      ),
      const _SocialLink(
        label: 'GitHub',
        identifier: 'auth_settings_social_github',
        icon: HugeIcons.strokeRoundedGithub,
        url: 'https://github.com/ente/ente',
      ),
      const _SocialLink(
        label: 'X',
        identifier: 'auth_settings_social_x',
        icon: HugeIcons.strokeRoundedNewTwitter,
        url: 'https://twitter.com/enteio',
      ),
      const _SocialLink(
        label: 'Mastodon',
        identifier: 'auth_settings_social_mastodon',
        icon: HugeIcons.strokeRoundedMastodon,
        url: 'https://fosstodon.org/@ente',
      ),
      const _SocialLink(
        label: 'Reddit',
        identifier: 'auth_settings_social_reddit',
        icon: HugeIcons.strokeRoundedReddit,
        url: 'https://reddit.com/r/enteio',
      ),
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: Spacing.xs,
      runSpacing: Spacing.xs,
      children: links.map((link) => _SocialIconButton(link: link)).toList(),
    );
  }
}

class _SocialIconButton extends StatelessWidget {
  const _SocialIconButton({required this.link});

  final _SocialLink link;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: link.identifier,
      child: IconButtonComponent(
        tooltip: link.label,
        shouldSurfaceExecutionStates: false,
        icon: HugeIcon(
          icon: link.icon,
          size: IconSizes.small,
          strokeWidth: 1.6,
        ),
        onTap: () => launchUrlString(
          link.url,
          mode: Platform.isAndroid
              ? LaunchMode.externalApplication
              : LaunchMode.platformDefault,
        ),
      ),
    );
  }
}

class _SocialLink {
  const _SocialLink({
    required this.label,
    required this.identifier,
    required this.icon,
    required this.url,
  });

  final String label;
  final String identifier;
  final List<List<dynamic>> icon;
  final String url;
}
