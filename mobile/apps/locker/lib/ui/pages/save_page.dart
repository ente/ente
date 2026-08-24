import 'dart:async';
import 'dart:io';

import "package:ente_components/ente_components.dart";
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:locker/ui/pages/account_credentials_page.dart';
import 'package:locker/ui/pages/personal_note_page.dart';
import 'package:locker/ui/pages/physical_records_page.dart';
import 'package:locker/ui/pages/scanner/scanner_capture_page.dart';

enum SaveOptionType { scanDocument, file, note, physicalRecord, credentials }

class SaveOption {
  const SaveOption({
    required this.type,
    required this.icon,
    required this.title,
    required this.description,
  });

  final SaveOptionType type;
  final List<List<dynamic>> icon;
  final String title;
  final String description;
}

const bool docScannerEnabled = kDebugMode;

List<SaveOption> saveOptions(BuildContext context) {
  final l10n = context.strings;
  return [
    if (docScannerEnabled)
      SaveOption(
        type: SaveOptionType.scanDocument,
        icon: HugeIcons.strokeRoundedFileScan,
        title: l10n.scanDocumentTitle,
        description: l10n.scanDocumentDescription,
      ),
    SaveOption(
      type: SaveOptionType.file,
      icon: HugeIcons.strokeRoundedFile01,
      title: l10n.saveFileTitle,
      description: l10n.saveFileDescription,
    ),
    SaveOption(
      type: SaveOptionType.note,
      icon: HugeIcons.strokeRoundedNote,
      title: l10n.personalNote,
      description: l10n.personalNoteDescription,
    ),
    SaveOption(
      type: SaveOptionType.physicalRecord,
      icon: HugeIcons.strokeRoundedBriefcase04,
      title: l10n.physicalRecords,
      description: l10n.physicalRecordsDescription,
    ),
    SaveOption(
      type: SaveOptionType.credentials,
      icon: HugeIcons.strokeRoundedSquareLock01,
      title: l10n.accountCredentials,
      description: l10n.accountCredentialsDescription,
    ),
  ];
}

void handleSaveOption(
  BuildContext context,
  SaveOptionType type, {
  required Future<bool> Function() onUploadDocument,
  required Future<bool> Function(List<File> files) onUploadFiles,
  VoidCallback? onCancelWithoutSaving,
}) {
  switch (type) {
    case SaveOptionType.scanDocument:
      if (!Platform.isAndroid && !Platform.isIOS) {
        showShortToast(context, context.strings.scannerNotSupportedOnDevice);
        onCancelWithoutSaving?.call();
        return;
      }
      unawaited(
        Navigator.of(context)
            .push<bool>(
              MaterialPageRoute(
                builder: (context) =>
                    ScannerCapturePage(onUploadFiles: onUploadFiles),
              ),
            )
            .then((didSave) {
              if (didSave != true) {
                onCancelWithoutSaving?.call();
              }
            }),
      );
      return;
    case SaveOptionType.file:
      unawaited(
        onUploadDocument().then((didUpload) {
          if (!didUpload) {
            onCancelWithoutSaving?.call();
          }
        }),
      );
      return;
    case SaveOptionType.note:
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              PersonalNotePage(onCancelWithoutSaving: onCancelWithoutSaving),
        ),
      );
      break;
    case SaveOptionType.physicalRecord:
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              PhysicalRecordsPage(onCancelWithoutSaving: onCancelWithoutSaving),
        ),
      );
      break;
    case SaveOptionType.credentials:
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => AccountCredentialsPage(
            onCancelWithoutSaving: onCancelWithoutSaving,
          ),
        ),
      );
      break;
  }
}

Future<void> showSaveBottomSheet(
  BuildContext context, {
  required Future<bool> Function() onUploadDocument,
  required Future<bool> Function(List<File> files) onUploadFiles,
}) {
  return showBottomSheetComponent<void>(
    context: context,
    builder: (_) => SaveBottomSheet(
      rootContext: context,
      onUploadDocument: onUploadDocument,
      onUploadFiles: onUploadFiles,
    ),
  );
}

class SaveBottomSheet extends StatelessWidget {
  const SaveBottomSheet({
    super.key,
    required this.rootContext,
    required this.onUploadDocument,
    required this.onUploadFiles,
  });

  final BuildContext rootContext;
  final Future<bool> Function() onUploadDocument;
  final Future<bool> Function(List<File> files) onUploadFiles;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    final options = saveOptions(context);

    return BottomSheetComponent(
      title: context.strings.saveToLocker,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.strings.informationDescription,
            style: TextStyles.body.copyWith(color: colors.textLight),
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < options.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    _buildSaveOption(
                      context,
                      rootContext: rootContext,
                      option: options[i],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveOption(
    BuildContext sheetContext, {
    required BuildContext rootContext,
    required SaveOption option,
  }) {
    final colors = sheetContext.componentColors;
    return MenuComponent(
      title: option.title,
      subtitle: option.description,
      subtitleMaxLines: 2,
      leading: HugeIcon(icon: option.icon, size: 20, color: colors.primary),
      trailing: Icon(Icons.chevron_right, color: colors.textBase),
      onTap: () {
        Navigator.of(sheetContext).pop();
        // Push the form route after the sheet has dismissed to avoid UI jank.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleSaveOption(rootContext, option.type);
        });
      },
    );
  }

  void _handleSaveOption(BuildContext context, SaveOptionType type) {
    final navigator = Navigator.of(context);
    void reopenSheet() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!navigator.mounted) {
          return;
        }
        showSaveBottomSheet(
          navigator.context,
          onUploadDocument: onUploadDocument,
          onUploadFiles: onUploadFiles,
        );
      });
    }

    handleSaveOption(
      context,
      type,
      onUploadDocument: onUploadDocument,
      onUploadFiles: onUploadFiles,
      onCancelWithoutSaving: reopenSheet,
    );
  }
}
