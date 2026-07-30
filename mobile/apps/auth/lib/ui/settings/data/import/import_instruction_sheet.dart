import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';

enum ImportInstructionResult { primary, secondary }

class ImportInstructionAction {
  const ImportInstructionAction({
    required this.label,
    required this.result,
    this.variant = ButtonComponentVariant.primary,
  });

  final String label;
  final ImportInstructionResult result;
  final ButtonComponentVariant variant;
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
  return showBottomSheetComponent<ImportInstructionResult>(
    context: context,
    builder: (sheetContext) {
      final colors = sheetContext.componentColors;
      final sheetContent =
          content ??
          Text(body!, style: TextStyles.body.copyWith(color: colors.textLight));
      final sheet = BottomSheetComponent(
        title: title,
        closeTooltip: cancelLabel,
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.45,
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
              shouldSurfaceExecutionStates: false,
              onTap: () => Navigator.of(sheetContext).pop(action.result),
            ),
        ],
      );
      return semanticsIdentifier == null
          ? sheet
          : Semantics(identifier: semanticsIdentifier, child: sheet);
    },
  );
}
