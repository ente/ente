import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/services/memory_share_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/alert_bottom_sheet.dart";
import "package:photos/ui/components/base_bottom_sheet.dart";
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/share_util.dart";

Future<bool?> showMemoryLinkDetailsSheet(
  BuildContext context, {
  required String shareUrl,
  required int shareId,
}) {
  final l10n = AppLocalizations.of(context);
  return showBaseBottomSheet<bool>(
    context,
    title: l10n.shareLink,
    child: Builder(
      builder: (context) {
        final colorScheme = getEnteColorScheme(context);
        final textTheme = getEnteTextTheme(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.memoryShareLinkDescription,
              style: textTheme.smallMuted.copyWith(
                color: colorScheme.contentLight,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colorScheme.fillDark,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 56, 20),
                    child: SelectableText(
                      shareUrl,
                      style: textTheme.small.copyWith(height: 1.5),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton(
                      tooltip: l10n.copyLink,
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: shareUrl));
                        if (context.mounted) {
                          showShortToast(context, l10n.linkCopiedToClipboard);
                        }
                      },
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedCopy01,
                        color: colorScheme.textBase,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ButtonWidgetV2(
              buttonType: ButtonTypeV2.primary,
              labelText: l10n.shareLink,
              shouldSurfaceExecutionStates: false,
              onTap: () async {
                unawaited(shareText(shareUrl, context: context));
              },
            ),
            const SizedBox(height: 12),
            Center(
              child: ButtonWidgetV2(
                buttonType: ButtonTypeV2.tertiaryCritical,
                labelText: l10n.deleteLink,
                shouldSurfaceExecutionStates: false,
                onTap: () async {
                  final shouldDelete = await showAlertBottomSheet<bool>(
                    context,
                    title: l10n.deleteLinkQuestion,
                    message: l10n.deleteMemoryLinkMessage,
                    assetPath: "assets/warning-grey.png",
                    buttons: [
                      ButtonWidgetV2(
                        buttonType: ButtonTypeV2.critical,
                        labelText: l10n.deleteLink,
                        onTap: () async {
                          try {
                            await MemoryShareService.instance.deleteMemoryShare(
                              shareId,
                            );
                            if (context.mounted) {
                              showShortToast(
                                context,
                                l10n.linkDeletedSuccessfully,
                              );
                              Navigator.of(context).pop(true);
                            }
                          } catch (_) {
                            if (context.mounted) {
                              showShortToast(context, l10n.somethingWentWrong);
                              Navigator.of(context).pop(false);
                            }
                          }
                        },
                      ),
                    ],
                  );
                  if (shouldDelete != true) {
                    return;
                  }
                  if (context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}
