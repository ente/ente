import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import "package:photos/theme/ente_theme.dart";

class CollageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CollageAppBar({
    super.key,
    required this.onSave,
    this.isSaveEnabled = true,
  });

  final VoidCallback onSave;
  final bool isSaveEnabled;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return AppBar(
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.strings.cancel, style: textTheme.body),
          ),
          TextButton(
            onPressed: isSaveEnabled ? onSave : null,
            child: Text(
              context.strings.saveCollage,
              style: textTheme.body.copyWith(
                color: isSaveEnabled
                    ? colorScheme.primary500
                    : colorScheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
