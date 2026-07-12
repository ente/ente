import 'package:clipboard/clipboard.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/theme/effects.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

Future<void> showNotesDialog(BuildContext context, String note) async {
  final trimmedNote = note.trim();
  if (trimmedNote.isEmpty) {
    return;
  }

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final colorScheme = getEnteColorScheme(dialogContext);
      final bool isDark = theme.brightness == Brightness.dark;
      final Color noteBackground = isDark
          ? const Color(0x29A75CFF)
          : const Color(0x0AA75CFF);
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(dialogContext).pop(),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 360,
                  maxHeight: 700,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.backgroundElevated,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: shadowFloatLight,
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              dialogContext.l10n.notes,
                              style: TextStyle(
                                color: colorScheme.textBase,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                height: 1.22,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 520),
                          decoration: ShapeDecoration(
                            color: noteBackground,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Stack(
                            children: [
                              Scrollbar(
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    20,
                                    20,
                                    72,
                                  ),
                                  child: SelectableText(
                                    trimmedNote,
                                    contextMenuBuilder:
                                        (context, EditableTextState state) {
                                          return AdaptiveTextSelectionToolbar.buttonItems(
                                            anchors: state.contextMenuAnchors,
                                            buttonItems:
                                                <ContextMenuButtonItem>[
                                                  ContextMenuButtonItem(
                                                    onPressed: () {
                                                      state.copySelection(
                                                        SelectionChangedCause
                                                            .toolbar,
                                                      );
                                                    },
                                                    type: ContextMenuButtonType
                                                        .copy,
                                                  ),
                                                  ContextMenuButtonItem(
                                                    onPressed: () {
                                                      state.selectAll(
                                                        SelectionChangedCause
                                                            .toolbar,
                                                      );
                                                    },
                                                    type: ContextMenuButtonType
                                                        .selectAll,
                                                  ),
                                                ],
                                          );
                                        },
                                    style: TextStyle(
                                      color: colorScheme.textBase,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      height: 1.64,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Material(
                                  color: Theme.of(dialogContext)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.7),
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () async {
                                      await FlutterClipboard.copy(trimmedNote);
                                      if (!dialogContext.mounted) return;
                                      Navigator.of(dialogContext).pop();
                                      showToast(
                                        dialogContext,
                                        dialogContext.l10n.copiedToClipboard,
                                      );
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: HugeIcon(
                                        icon: HugeIcons.strokeRoundedCopy01,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
