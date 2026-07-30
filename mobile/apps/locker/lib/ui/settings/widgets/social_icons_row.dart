import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:url_launcher/url_launcher_string.dart";

/// A row of social media icon buttons
class SocialIconsRow extends StatelessWidget {
  const SocialIconsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SocialIconButton(
          icon: HugeIcons.strokeRoundedDiscord,
          url: "https://ente.com/discord",
        ),
        SizedBox(width: 8),
        _SocialIconButton(
          icon: HugeIcons.strokeRoundedYoutube,
          url: "https://www.youtube.com/@entestudio",
        ),
        SizedBox(width: 8),
        _SocialIconButton(
          icon: HugeIcons.strokeRoundedGithub,
          url: "https://github.com/ente",
        ),
        SizedBox(width: 8),
        _SocialIconButton(
          icon: HugeIcons.strokeRoundedNewTwitter,
          url: "https://twitter.com/enteio",
        ),
        SizedBox(width: 8),
        _SocialIconButton(
          icon: HugeIcons.strokeRoundedMastodon,
          url: "https://fosstodon.org/@ente",
        ),
        SizedBox(width: 8),
        _SocialIconButton(
          icon: HugeIcons.strokeRoundedReddit,
          url: "https://reddit.com/r/enteio",
        ),
      ],
    );
  }
}

class _SocialIconButton extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String url;

  const _SocialIconButton({required this.icon, required this.url});

  @override
  Widget build(BuildContext context) {
    return IconButtonComponent(
      variant: IconButtonComponentVariant.secondary,
      shouldSurfaceExecutionStates: false,
      icon: HugeIcon(icon: icon, size: IconSizes.small, strokeWidth: 1.6),
      onTap: () async {
        await launchUrlString(url, mode: LaunchMode.externalApplication);
      },
    );
  }
}
