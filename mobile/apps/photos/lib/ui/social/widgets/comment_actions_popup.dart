import "package:ente_icons/ente_icons.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/theme/ente_theme.dart";

class CommentActionsPopup extends StatelessWidget {
  final bool isLiked;
  final VoidCallback onLikeTap;
  final VoidCallback onReplyTap;
  final VoidCallback? onDeleteTap;
  final bool showDelete;

  const CommentActionsPopup({
    required this.isLiked,
    required this.onLikeTap,
    required this.onReplyTap,
    this.onDeleteTap,
    this.showDelete = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final backgroundColor = isDarkMode ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActionItem(
              icon: isLiked ? EnteIcons.likeFilled : EnteIcons.likeStroke,
              iconColor: isLiked ? const Color(0xFF08C225) : null,
              label: l10n.like,
              onTap: onLikeTap,
              textStyle: textTheme.mini.copyWith(
                height: 19 / 12,
                letterSpacing: -0.36,
              ),
              defaultIconColor: colorScheme.textBase,
            ),
            _ActionItem(
              icon: EnteIcons.reply,
              label: l10n.reply,
              onTap: onReplyTap,
              textStyle: textTheme.mini.copyWith(
                height: 19 / 12,
                letterSpacing: -0.36,
              ),
              defaultIconColor: colorScheme.textBase,
            ),
            if (showDelete)
              _ActionItem(
                icon: Icons.delete_outline_rounded,
                label: l10n.delete,
                onTap: onDeleteTap!,
                textStyle: textTheme.mini.copyWith(
                  height: 19 / 12,
                  letterSpacing: -0.36,
                ),
                defaultIconColor: colorScheme.textBase,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final VoidCallback onTap;
  final TextStyle textStyle;
  final Color defaultIconColor;

  const _ActionItem({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.onTap,
    required this.textStyle,
    required this.defaultIconColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 40, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor ?? defaultIconColor),
            const SizedBox(width: 8),
            Text(label, style: textStyle.copyWith(color: defaultIconColor)),
          ],
        ),
      ),
    );
  }
}
