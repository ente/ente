import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import "package:pro_image_editor/pro_image_editor.dart";

class ImageEditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ImageEditorAppBar({
    super.key,
    required this.configs,
    this.undo,
    this.redo,
    required this.done,
    required this.close,
    this.enableUndo = false,
    this.enableRedo = false,
    this.isMainEditor = false,
  });

  final ProImageEditorConfigs configs;
  final Function()? undo;
  final Function()? redo;
  final Function() done;
  final Function() close;
  final bool enableUndo;
  final bool enableRedo;
  final bool isMainEditor;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final actionTextStyle = TextStyles.large.copyWith(color: colors.textBase);
    return AppBar(
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () {
              enableUndo ? close() : Navigator.of(context).pop();
            },
            child: Text(context.strings.cancel, style: actionTextStyle),
          ),
          if (undo != null && redo != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: context.strings.undo,
                  onPressed: () {
                    undo != null ? undo!() : null;
                  },
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedUndo03,
                    color: enableUndo ? colors.textBase : colors.textLight,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: context.strings.redo,
                  onPressed: () {
                    redo != null ? redo!() : null;
                  },
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedRedo03,
                    color: enableRedo ? colors.textBase : colors.textLight,
                  ),
                ),
              ],
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: TextButton(
              key: ValueKey(isMainEditor ? 'save_copy' : 'done'),
              onPressed: done,
              child: Text(
                isMainEditor ? context.strings.saveCopy : context.strings.done,
                style: actionTextStyle.copyWith(
                  color: isMainEditor
                      ? (enableUndo ? colors.primary : colors.textLight)
                      : colors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
