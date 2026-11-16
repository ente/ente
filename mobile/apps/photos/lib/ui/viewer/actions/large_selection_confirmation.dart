import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";

const _largeSelectionThreshold = 100;

Future<bool> confirmIfLargeSelection(BuildContext context, int count) async {
  if (count <= _largeSelectionThreshold) return true;
  final confirmed = await showBottomSheetComponent<bool>(
    context: context,
    builder: (sheetContext) => BottomSheetComponent(
      title: sheetContext.strings.selectAllConfirmationTitle(count: count),
      message: sheetContext.strings.selectAllConfirmationBody,
      closeTooltip: sheetContext.strings.close,
      actions: [
        ButtonComponent(
          label: sheetContext.strings.selectAll,
          shouldSurfaceExecutionStates: false,
          onTap: () => Navigator.of(sheetContext).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
