import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/theme/ente_theme.dart";
import "package:url_launcher/url_launcher_string.dart";

/// A row of social media icons for the settings page.
/// Figma specs: 32x32 containers, 8px gap, icons 16-19px, strokeBase color
class SocialIconsRow extends StatelessWidget {
  const SocialIconsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    const socialLinks = [
      _SocialLink(
        icon: HugeIcons.strokeRoundedDiscord,
        url: "https://ente.com/discord",
        label: "Discord",
      ),
      _SocialLink(
        icon: HugeIcons.strokeRoundedYoutube,
        url: "https://www.youtube.com/@entestudio",
        label: "YouTube",
      ),
      _SocialLink(
        icon: HugeIcons.strokeRoundedGithub,
        url: "https://github.com/ente/ente",
        label: "GitHub",
      ),
      _SocialLink(
        icon: HugeIcons.strokeRoundedNewTwitter,
        url: "https://twitter.com/enteio",
        label: "X",
      ),
      _SocialLink(
        icon: HugeIcons.strokeRoundedMastodon,
        url: "https://fosstodon.org/@ente",
        label: "Mastodon",
      ),
      _SocialLink(
        icon: HugeIcons.strokeRoundedReddit,
        url: "https://reddit.com/r/enteio",
        label: "Reddit",
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: socialLinks.map((link) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: () => _launchUrl(link.url),
            child: Semantics(
              label: link.label,
              button: true,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: HugeIcon(
                    icon: link.icon,
                    color: colorScheme.menuItemIconStroke,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _launchUrl(String url) async {
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }
}

class _SocialLink {
  final List<List<dynamic>> icon;
  final String url;
  final String label;

  const _SocialLink({
    required this.icon,
    required this.url,
    required this.label,
  });
}
