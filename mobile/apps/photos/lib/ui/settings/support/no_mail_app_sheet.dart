import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/constants.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/email_util.dart";

Future<void> showNoMailAppSheet(
  BuildContext context, {
  required String toEmail,
  required String subject,
  required String message,
  String? deviceInfo,
  String? logsLabel,
  String? logsFilePath,
}) async {
  await showBottomSheetComponent<void>(
    context: context,
    builder: (_) => BottomSheetComponent(
      title: AppLocalizations.of(context).noEmailAppFound,
      content: NoMailAppSheet(
        toEmail: toEmail,
        subject: subject,
        message: message,
        deviceInfo: deviceInfo,
        logsLabel: logsLabel,
        logsFilePath: logsFilePath,
      ),
    ),
  );
}

class NoMailAppSheet extends StatelessWidget {
  static const _toFieldLabel = "To";

  final String toEmail;
  final String subject;
  final String message;
  final String? deviceInfo;
  final String? logsLabel;
  final String? logsFilePath;

  const NoMailAppSheet({
    required this.toEmail,
    required this.subject,
    required this.message,
    this.deviceInfo,
    this.logsLabel,
    this.logsFilePath,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final copyFields = <_CopyFieldData>[
      _CopyFieldData(label: l10n.subject, value: subject),
      _CopyFieldData(label: l10n.message, value: message),
      if (deviceInfo != null && deviceInfo!.trim().isNotEmpty)
        _CopyFieldData(label: l10n.deviceInfo, value: deviceInfo!),
      if (logsLabel != null && logsLabel!.trim().isNotEmpty)
        _CopyFieldData(
          label: l10n.logs,
          value: logsLabel!,
          logsFilePath: logsFilePath,
          note: l10n.logsNotCopiedDownloadNote,
        ),
    ];
    final maxSheetBodyHeight = MediaQuery.sizeOf(context).height * 0.75;
    final estimatedSheetBodyHeight = 240 + (120 * copyFields.length);
    final sheetBodyHeight = estimatedSheetBodyHeight > maxSheetBodyHeight
        ? maxSheetBodyHeight
        : estimatedSheetBodyHeight.toDouble();

    return SizedBox(
      height: sheetBodyHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.noEmailAppBody(email: toEmail),
                    style: TextStyles.mini.copyWith(
                      color: context.componentColors.textLight,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  for (int i = 0; i < copyFields.length; i++) ...[
                    _CopyField(
                      data: copyFields[i],
                      onCopy: () async {
                        await Clipboard.setData(
                          ClipboardData(text: copyFields[i].value),
                        );
                        if (context.mounted) {
                          showShortToast(context, l10n.copied);
                        }
                      },
                      onExport: copyFields[i].logsFilePath == null
                          ? null
                          : () async {
                              await exportLogs(
                                context,
                                copyFields[i].logsFilePath!,
                              );
                            },
                    ),
                    if (i != copyFields.length - 1)
                      const SizedBox(height: Spacing.md),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          ButtonComponent(
            label: l10n.copyAllToClipboard,
            onTap: () async {
              await Clipboard.setData(
                ClipboardData(text: _buildCopyAllPayload(l10n)),
              );
              if (context.mounted) {
                showShortToast(context, l10n.copied);
              }
            },
          ),
        ],
      ),
    );
  }

  String _buildCopyAllPayload(AppLocalizations l10n) {
    final shouldIncludeLogsInCopyAll =
        logsFilePath == null &&
        logsLabel != null &&
        logsLabel!.trim().isNotEmpty;
    final items = <String>[
      "$_toFieldLabel: $supportEmail",
      "${l10n.subject}: $subject",
      "${l10n.message}: $message",
      if (deviceInfo != null && deviceInfo!.trim().isNotEmpty)
        "${l10n.deviceInfo}: ${deviceInfo!.trim()}",
      if (shouldIncludeLogsInCopyAll) "${l10n.logs}: ${logsLabel!.trim()}",
    ];
    return items.join("\n\n");
  }
}

class _CopyFieldData {
  final String label;
  final String value;
  final String? logsFilePath;
  final String? note;

  const _CopyFieldData({
    required this.label,
    required this.value,
    this.logsFilePath,
    this.note,
  });
}

class _CopyField extends StatelessWidget {
  final _CopyFieldData data;
  final Future<void> Function() onCopy;
  final Future<void> Function()? onExport;

  const _CopyField({required this.data, required this.onCopy, this.onExport});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final isExportAction = onExport != null;
    final onTap = isExportAction ? onExport! : onCopy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            data.label,
            style: TextStyles.mini.copyWith(color: colors.textLight),
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: colors.fillLight,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                10,
                Spacing.sm,
                10,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      data.value,
                      style: TextStyles.mini.copyWith(color: colors.textBase),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Padding(
                    padding: const EdgeInsets.all(7),
                    child: HugeIcon(
                      icon: isExportAction
                          ? HugeIcons.strokeRoundedDownload04
                          : HugeIcons.strokeRoundedCopy01,
                      size: 18,
                      color: colors.textLighter,
                      strokeWidth: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: const SizedBox(width: 44, height: 44),
                ),
              ),
            ),
          ],
        ),
        if (data.note != null && data.note!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              data.note!,
              style: TextStyles.mini.copyWith(color: colors.textLight),
            ),
          ),
        ],
      ],
    );
  }
}
