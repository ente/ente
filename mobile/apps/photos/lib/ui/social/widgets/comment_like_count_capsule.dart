import "package:ente_icons/ente_icons.dart";
import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";

class CommentLikeCountCapsule extends StatelessWidget {
  final int likeCount;
  final VoidCallback? onTap;

  const CommentLikeCountCapsule({
    required this.likeCount,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF212121)
        : const Color(0xFFF0F0F0);
    final textColor = isDark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF131313);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(left: 6, right: 8, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(
            color: isDark
                ? const Color(0xFF0E0E0E)
                : colorScheme.backgroundElevated,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(42),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              EnteIcons.likeFilled,
              size: 14,
              color: Color(0xFF08C225),
            ),
            const SizedBox(width: 2),
            Text(
              likeCount.toString(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: textColor,
                height: 14 / 10,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
