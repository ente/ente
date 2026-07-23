import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/gradient_button.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";

/// Shows a bottom sheet confirmation dialog for deleting a comment.
/// Returns true if confirmed, null if cancelled.
Future<bool?> showDeleteCommentConfirmationDialog(
  BuildContext context, {
  required String commentText,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _DeleteCommentConfirmationSheet(commentText: commentText),
  );
}

class _DeleteCommentConfirmationSheet extends StatelessWidget {
  final String commentText;

  const _DeleteCommentConfirmationSheet({required this.commentText});

  String _truncateComment(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return "${text.substring(0, maxLength)}....";
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final truncatedComment = _truncateComment(commentText, 30);

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF0E0E0E)
            : colorScheme.backgroundElevated,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Center(
                      child: Image.asset(
                        "assets/ducky_garbage_bin_opened.png",
                        height: 180,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 0,
                    child: IconButtonWidget(
                      iconButtonType: IconButtonType.rounded,
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
              Text(
                l10n.areYouSure,
                style: textTheme.h3Bold,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.deleteCommentConfirmation(comment: truncatedComment),
                style: textTheme.body.copyWith(color: colorScheme.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  onTap: () => Navigator.of(context).pop(true),
                  text: l10n.deleteComment,
                  linearGradientColors: const [
                    Color(0xFFF63A3A),
                    Color(0xFFF63A3A),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
