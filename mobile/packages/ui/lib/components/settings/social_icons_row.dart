import 'package:ente_components/ente_components.dart';
import 'package:ente_components/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SocialIconsRow extends StatelessWidget {
  const SocialIconsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: Spacing.xs,
      runSpacing: Spacing.xs,
      children: _socialLinks
          .map(
            (link) => Semantics(
              label: link.label,
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
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

const _socialLinks = [
  _SocialLink(
    label: 'Discord',
    icon: HugeIcons.strokeRoundedDiscord,
    url: 'https://ente.com/discord',
  ),
  _SocialLink(
    label: 'YouTube',
    icon: HugeIcons.strokeRoundedYoutube,
    url: 'https://www.youtube.com/@entestudio',
  ),
  _SocialLink(
    label: 'GitHub',
    icon: HugeIcons.strokeRoundedGithub,
    url: 'https://github.com/ente/ente',
  ),
  _SocialLink(
    label: 'X',
    icon: HugeIcons.strokeRoundedNewTwitter,
    url: 'https://twitter.com/enteio',
  ),
  _SocialLink(
    label: 'Mastodon',
    icon: HugeIcons.strokeRoundedMastodon,
    url: 'https://fosstodon.org/@ente',
  ),
  _SocialLink(
    label: 'Reddit',
    icon: HugeIcons.strokeRoundedReddit,
    url: 'https://reddit.com/r/enteio',
  ),
];

class _SocialLink {
  const _SocialLink({
    required this.label,
    required this.icon,
    required this.url,
  });

  final String label;
  final List<List<dynamic>> icon;
  final String url;
}
