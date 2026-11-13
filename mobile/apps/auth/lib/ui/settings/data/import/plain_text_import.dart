import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/plain_text_import_parser.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class PlainTextImport extends StatelessWidget {
  const PlainTextImport({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.importInstruction,
          style: TextStyles.body.copyWith(
            color: context.componentColors.textLight,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Container(
          decoration: BoxDecoration(
            color: context.componentColors.fillLight,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: const Padding(
            padding: EdgeInsets.all(Spacing.md),
            child: Text(
              "otpauth://totp/provider.com:you@email.com?secret=YOUR_SECRET",
              style: TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Text(
          l10n.importCodeDelimiterInfo,
          style: TextStyles.body.copyWith(
            color: context.componentColors.textLight,
          ),
        ),
      ],
    );
  }
}

Future<void> showImportInstructionDialog(BuildContext context) async {
  final l10n = context.strings;
  await showFileImportInstruction(
    context: context,
    title: l10n.importCodes,
    actionLabel: l10n.selectFile,
    semanticsIdentifier: 'auth_import_instruction_plain_text',
    content: const PlainTextImport(),
    onImport: () => _pickImportFile(context),
  );
}

Future<void> _pickImportFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    logger: Logger('PlainTextImport'),
    logMessage: 'Failed to import plain-text codes',
    errorMessage: (context, _) => context.strings.importFailureDesc,
    process: (path, _) async {
      final contents = await readPickedImportFileAsString(path);
      return saveImportedCodes(parsePlainTextImport(contents));
    },
  );
}
