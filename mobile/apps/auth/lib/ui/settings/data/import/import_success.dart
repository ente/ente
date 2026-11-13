import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';

Future<void> importSuccessDialog(BuildContext context, int count) async {
  final l10n = context.strings;
  await showBottomSheetComponent<void>(
    context: context,
    builder: (sheetContext) => Semantics(
      identifier: 'auth_import_success',
      child: BottomSheetComponent(
        title: l10n.importSuccessTitle,
        message: l10n.importSuccessDesc(count: count),
        closeTooltip: l10n.close,
        actions: [
          ButtonComponent(
            label: l10n.ok,
            shouldSurfaceExecutionStates: false,
            onTap: () => Navigator.of(sheetContext).pop(),
          ),
        ],
      ),
    ),
  );
}
