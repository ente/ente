import 'dart:async';

import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:locker/l10n/l10n.dart';
import 'package:locker/ui/pages/account_credentials_page.dart';
import 'package:locker/ui/pages/personal_note_page.dart';
import 'package:locker/ui/pages/physical_records_page.dart';

enum SaveOptionType { document, note, physicalRecord, credentials }

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

List<SaveOption> saveOptions(BuildContext context) {
  final l10n = context.l10n;
  return [
    SaveOption(
      type: SaveOptionType.document,
      icon: HugeIcons.strokeRoundedFile01,
      title: l10n.saveDocumentTitle,
      description: l10n.saveDocumentDescription,
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
  VoidCallback? onCancelWithoutSaving,
}) {
  switch (type) {
    case SaveOptionType.document:
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
}) {
  return showBottomSheetComponent<void>(
    context: context,
    builder: (_) => SaveBottomSheet(
      rootContext: context,
      onUploadDocument: onUploadDocument,
    ),
  );
}

class SaveBottomSheet extends StatelessWidget {
  const SaveBottomSheet({
    super.key,
    required this.rootContext,
    required this.onUploadDocument,
  });

  final BuildContext rootContext;
  final Future<bool> Function() onUploadDocument;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    final options = saveOptions(context);

    return BottomSheetComponent(
      title: context.l10n.saveToLocker,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.informationDescription,
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
        );
      });
    }

    handleSaveOption(
      context,
      type,
      onUploadDocument: onUploadDocument,
      onCancelWithoutSaving: reopenSheet,
    );
  }
}
