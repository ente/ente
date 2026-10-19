import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:ente_utils/share_utils.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/services/files/links/links_service.dart";
import "package:locker/services/files/sync/models/file.dart";
import "package:locker/ui/components/locker_progress_dialog.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";
import "package:locker/utils/error_sheet.dart";

Future<void> showShareLinkSheet(
  BuildContext context,
  String url,
  String linkID,
  EnteFile file,
) async {
  final rootContext = context;

  await showBottomSheetComponent<void>(
    context: context,
    builder: (_) =>
        ShareLinkSheet(url: url, file: file, rootContext: rootContext),
  );
}

class ShareLinkSheet extends StatefulWidget {
  final String url;
  final EnteFile file;
  final BuildContext rootContext;

  const ShareLinkSheet({
    super.key,
    required this.url,
    required this.file,
    required this.rootContext,
  });

  @override
  State<ShareLinkSheet> createState() => _ShareLinkSheetState();
}

class _ShareLinkSheetState extends State<ShareLinkSheet> {
  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;

    return BottomSheetComponent(
      title: l10n.share,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.shareThisLink,
            style: TextStyles.body.copyWith(color: colors.textLight),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: colors.fillLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          widget.url,
                          style: TextStyles.body.copyWith(
                            color: colors.textBase,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Center(
                    child: IconButton(
                      onPressed: () => _copyToClipboard(),
                      visualDensity: VisualDensity.compact,
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedCopy01,
                        color: colors.textBase,
                        size: 18,
                      ),
                      tooltip: 'Copy link',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        ButtonComponent(
          label: l10n.shareLink,
          onTap: () async {
            Navigator.of(context).pop();
            await shareText(widget.url, context: widget.rootContext);
          },
        ),
        ButtonComponent(
          label: l10n.deleteLink,
          variant: ButtonComponentVariant.tertiaryCritical,
          onTap: () async {
            Navigator.of(context).pop();
            await _deleteShareLink(widget.rootContext);
          },
        ),
      ],
    );
  }

  Future<void> _deleteShareLink(BuildContext context) async {
    final l10n = context.strings;

    final confirmed = await showBottomSheetComponent<bool>(
      context: context,
      builder: (_) => BottomSheetComponent(
        title: l10n.deleteLinkQuestion,
        message: l10n.deleteShareLinkConfirmation,
        illustration: LockerBottomSheetIllustration.fileDelete,
        actions: [
          ButtonComponent(
            label: l10n.delete,
            variant: ButtonComponentVariant.critical,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      LockerProgressDialog? dialog;
      try {
        dialog = await showLockerProgressDialog(
          context,
          l10n.deletingShareLink,
        );
        await LinksService.instance.deleteLink(widget.file.uploadedFileID!);
        await dialog.hide();

        if (context.mounted) {
          showToast(context, l10n.linkDeletedSuccessfully);
        }
      } catch (e) {
        await dialog?.hide();

        if (context.mounted) {
          await showLockerErrorSheet(context, e);
        }
      }
    }
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (mounted) {
      showShortToast(context, 'Link copied to clipboard');
    }
  }
}
