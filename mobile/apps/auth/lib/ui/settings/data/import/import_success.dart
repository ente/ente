import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';

Future<void> importSuccessDialog(BuildContext context, int count) async {
  final l10n = context.l10n;
  await showBottomSheetComponent<void>(
    context: context,
    builder: (sheetContext) => Semantics(
      identifier: 'auth_import_success',
      child: BottomSheetComponent(
        title: l10n.importSuccessTitle,
        message: l10n.importSuccessDesc(count),
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
