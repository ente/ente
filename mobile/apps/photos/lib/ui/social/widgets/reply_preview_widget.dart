import "package:flutter/material.dart";
import "package:photos/extensions/user_extension.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/social/comment.dart";
import "package:photos/theme/ente_theme.dart";

class ReplyPreviewWidget extends StatelessWidget {
  final Comment replyingTo;
  final User replyingToUser;
  final int currentUserID;
  final VoidCallback onDismiss;

  const ReplyPreviewWidget({
    required this.replyingTo,
    required this.replyingToUser,
    required this.currentUserID,
    required this.onDismiss,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Container(
      // padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: const Color(0xFF8C8C8C),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    replyingToUser.id == currentUserID
                        ? l10n.replyingToYou
                        : l10n.replyingTo(
                            name:
                                replyingToUser.displayName ??
                                replyingToUser.email,
                          ),
                    style: textTheme.tiny.copyWith(
                      color: colorScheme.textBase,
                      height: 14 / 10.0,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    replyingTo.data,
                    style: textTheme.small.copyWith(
                      color: colorScheme.textBase,
                      height: 22 / 14.0,
                      letterSpacing: -0.28,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close, size: 18, color: colorScheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
