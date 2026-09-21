import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';

enum ImportInstructionResult { primary, secondary }

class ImportInstructionAction {
  const ImportInstructionAction({
    required this.label,
    required this.result,
    this.variant = ButtonComponentVariant.primary,
    this.onTap,
  });

  final String label;
  final ImportInstructionResult result;
  final ButtonComponentVariant variant;
  final FutureOr<void> Function()? onTap;
}

Future<ImportInstructionResult?> showImportInstructionSheet({
  required BuildContext context,
  required String title,
  required String cancelLabel,
  required List<ImportInstructionAction> actions,
  String? body,
  Widget? content,
  String? semanticsIdentifier,
}) {
  assert(body != null || content != null);
  final hasAsyncAction = actions.any((action) => action.onTap != null);
  ImportInstructionAction? executingAction;
  return showBottomSheetComponent<ImportInstructionResult>(
    context: context,
    isDismissible: !hasAsyncAction,
    enableDrag: !hasAsyncAction,
    builder: (_) {
      return StatefulBuilder(
        builder: (context, setState) {
          final colors = context.componentColors;
          final sheetContent =
              content ??
              Text(
                body!,
                style: TextStyles.body.copyWith(color: colors.textLight),
              );
          final sheet = BottomSheetComponent(
            title: title,
            closeTooltip: cancelLabel,
            showCloseButton: executingAction == null,
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: SizedBox(
                width: double.infinity,
                child: SingleChildScrollView(child: sheetContent),
              ),
            ),
            actions: [
              for (final action in actions)
                ButtonComponent(
                  label: action.label,
                  variant: action.variant,
                  isDisabled:
                      executingAction != null && executingAction != action,
                  shouldSurfaceExecutionStates: action.onTap != null,
                  onTap: action.onTap == null
                      ? () => Navigator.of(context).pop(action.result)
                      : () async {
                          setState(() => executingAction = action);
                          try {
                            await action.onTap!();
                            if (context.mounted &&
                                ModalRoute.of(context)?.isCurrent == true) {
                              Navigator.of(context).pop(action.result);
                            }
                          } finally {
                            if (context.mounted &&
                                ModalRoute.of(context)?.isCurrent == true) {
                              setState(() => executingAction = null);
                            }
                          }
                        },
                ),
            ],
          );
          return semanticsIdentifier == null
              ? sheet
              : Semantics(identifier: semanticsIdentifier, child: sheet);
        },
      );
    },
  );
}
