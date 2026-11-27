import "package:ente_auth/store/code_display_store.dart";
import "package:ente_auth/theme/ente_theme.dart";
import 'package:ente_components/ente_components.dart';
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";

class TagChip extends StatefulWidget {
  const TagChip({
    super.key,
    required this.label,
    this.selected = false,
    this.leading,
    this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<TagChip> createState() => _TagChipState();
}

class _TagChipState extends State<TagChip> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final foreground = widget.selected ? colors.specialWhite : colors.textLight;
    return FocusableActionDetector(
      enabled: widget.onTap != null,
      mouseCursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (value) => setState(() => _hasFocus = value),
      child: Semantics(
        button: true,
        selected: widget.selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTap: widget.onLongPress,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, maxWidth: 200),
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.xl,
              vertical: Spacing.md,
            ),
            decoration: BoxDecoration(
              color: widget.selected
                  ? colors.primary
                  : getEnteColorScheme(context).fillFaint,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(
                color: _hasFocus ? colors.textBase : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.leading != null) ...[
                  IconTheme(
                    data: IconThemeData(
                      color: foreground,
                      size: IconSizes.small,
                    ),
                    child: widget.leading!,
                  ),
                  const SizedBox(width: Spacing.xs),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.body.copyWith(color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _TagAction { edit, delete }

Future<void> showTagActions(BuildContext context, String tag) async {
  final l10n = context.strings;
  final action = await showBottomSheetComponent<_TagAction>(
    context: context,
    builder: (sheetContext) => Semantics(
      identifier: 'auth_tag_actions_sheet',
      child: BottomSheetComponent(
        title: tag,
        closeTooltip: l10n.close,
        content: MenuGroupComponent(
          showDividers: true,
          items: [
            MenuComponent(
              title: l10n.edit,
              leading: const Icon(Icons.edit_outlined),
              onTap: () => Navigator.of(sheetContext).pop(_TagAction.edit),
            ),
            MenuComponent(
              title: l10n.delete,
              titleColor: sheetContext.componentColors.warning,
              iconColor: sheetContext.componentColors.warning,
              leading: const Icon(Icons.delete_outline),
              onTap: () => Navigator.of(sheetContext).pop(_TagAction.delete),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted || action == null) return;

  switch (action) {
    case _TagAction.edit:
      await CodeDisplayStore.instance.showEditDialog(context, tag);
    case _TagAction.delete:
      await CodeDisplayStore.instance.showDeleteTagDialog(context, tag);
  }
}
