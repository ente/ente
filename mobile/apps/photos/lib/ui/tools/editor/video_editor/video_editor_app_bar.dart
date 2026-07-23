import 'package:flutter/material.dart';
import "package:photos/ente_theme_data.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/theme/ente_theme.dart";

class VideoEditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  const VideoEditorAppBar({
    super.key,
    required this.onCancel,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    this.isPrimaryEnabled = true,
  });

  final VoidCallback onCancel;
  final String primaryActionLabel;
  final VoidCallback onPrimaryAction;
  final bool isPrimaryEnabled;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return AppBar(
      elevation: 0,
      backgroundColor: colorScheme.backgroundColour,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: onCancel,
            child: Text(
              AppLocalizations.of(context).cancel,
              style: textTheme.body,
            ),
          ),
          TextButton(
            onPressed: isPrimaryEnabled ? onPrimaryAction : null,
            child: Text(
              primaryActionLabel,
              style: textTheme.body.copyWith(
                color: isPrimaryEnabled
                    ? Theme.of(context).colorScheme.imageEditorPrimaryColor
                    : colorScheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
