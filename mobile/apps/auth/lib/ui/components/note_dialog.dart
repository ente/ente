import 'package:clipboard/clipboard.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

Future<void> showNotesDialog(BuildContext context, String note) async {
  final trimmedNote = note.trim();
  if (trimmedNote.isEmpty) return;

  await showBottomSheetComponent<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheetContext) {
      final colors = sheetContext.componentColors;
      return Semantics(
        identifier: 'auth_notes_sheet',
        child: BottomSheetComponent(
          title: sheetContext.l10n.notes,
          closeTooltip: sheetContext.l10n.close,
          content: Container(
            width: double.infinity,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.55,
            ),
            padding: const EdgeInsets.all(Spacing.xl),
            decoration: BoxDecoration(
              color: colors.fillLight,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                child: SelectableText(
                  trimmedNote,
                  contextMenuBuilder: (context, state) {
                    return AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: state.contextMenuAnchors,
                      buttonItems: <ContextMenuButtonItem>[
                        ContextMenuButtonItem(
                          onPressed: () => state.copySelection(
                            SelectionChangedCause.toolbar,
                          ),
                          type: ContextMenuButtonType.copy,
                        ),
                        ContextMenuButtonItem(
                          onPressed: () =>
                              state.selectAll(SelectionChangedCause.toolbar),
                          type: ContextMenuButtonType.selectAll,
                        ),
                      ],
                    );
                  },
                  style: TextStyles.body.copyWith(color: colors.textBase),
                ),
              ),
            ),
          ),
          actions: [
            ButtonComponent(
              label: MaterialLocalizations.of(sheetContext).copyButtonLabel,
              variant: ButtonComponentVariant.secondary,
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedCopy01,
                size: IconSizes.small,
              ),
              onTap: () async {
                await FlutterClipboard.copy(trimmedNote);
                if (!sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                if (!context.mounted) return;
                showToast(context, context.l10n.copiedToClipboard);
              },
            ),
          ],
        ),
      );
    },
  );
}
