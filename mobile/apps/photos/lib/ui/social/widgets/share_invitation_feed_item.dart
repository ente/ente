import "package:ente_components/theme/text_styles.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/models/collection/collection_invitation.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/social/widgets/resolved_social_user_name.dart";

class ShareInvitationFeedItem extends StatelessWidget {
  const ShareInvitationFeedItem({
    required this.invitation,
    required this.onTap,
    super.key,
  });

  final CollectionInvitation invitation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = getEnteColorScheme(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDark ? colors.backgroundElevated : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ResolvedSocialUserName(
                  user: invitation.inviter,
                  builder: (context, inviterName) => Text(
                    context.strings.shareInviteFeedEntry(
                      inviter: inviterName,
                      album: invitation.albumName,
                    ),
                    style: TextStyles.body.copyWith(color: colors.textBase),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
