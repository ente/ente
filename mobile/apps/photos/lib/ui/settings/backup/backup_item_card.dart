import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import "package:logging/logging.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/backup/backup_item.dart";
import "package:photos/models/backup/backup_item_status.dart";
import "package:photos/module/upload/service/file_uploader.dart";
import 'package:photos/theme/ente_theme.dart';
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/utils/email_util.dart";

class BackupItemCard extends StatefulWidget {
  const BackupItemCard({super.key, required this.item});

  final BackupItem item;

  @override
  State<BackupItemCard> createState() => _BackupItemCardState();
}

class _BackupItemCardState extends State<BackupItemCard> {
  String? folderName;
  bool showThumbnail = false;
  final _logger = Logger("BackupItemCard");

  @override
  void initState() {
    super.initState();
    folderName = widget.item.file.deviceFolder ?? '';

    // Delay rendering of the thumbnail for 0.5 seconds
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          showThumbnail = true;
        });
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final hasError = widget.item.error != null;

    return GestureDetector(
      onTap: () {
        routeToPage(
          context,
          DetailPage(
            DetailPageConfiguration(
              List.unmodifiable([widget.item.file]),
              0,
              "collection",
            ),
          ),
          forceCustomPageRoute: true,
        );
      },
      child: Container(
        height: 60,
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: colorScheme.fillFaint.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: showThumbnail
                    ? ThumbnailWidget(
                        widget.item.file,
                        shouldShowSyncStatus: false,
                      )
                    : Container(
                        color: colorScheme.fillFaint, // Placeholder color
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.file.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      height: 20 / 16,
                      color: Theme.of(context).brightness == Brightness.light
                          ? const Color(0xFF000000)
                          : const Color(0xFFFFFFFF),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    folderName ?? "",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 17 / 14,
                      color: Theme.of(context).brightness == Brightness.light
                          ? const Color.fromRGBO(0, 0, 0, 0.7)
                          : const Color.fromRGBO(255, 255, 255, 0.7),
                    ),
                  ),
                ],
              ),
            ),
            if (hasError) const SizedBox(width: 12),
            if (hasError)
              SizedBox(
                height: 48,
                width: 48,
                child: IconButton(
                  icon: Icon(
                    Icons.error_outline,
                    color: getEnteColorScheme(context).fillBase,
                  ),
                  onPressed: () {
                    showBottomSheetComponent<void>(
                      context: context,
                      isDismissible: true,
                      builder: (_) => BottomSheetComponent(
                        title: AppLocalizations.of(context).backupFailed,
                        message: AppLocalizations.of(
                          context,
                        ).sorryBackupFailedDesc,
                        illustration: Image.asset("assets/warning-grey.png"),
                        actions: [
                          ButtonComponent(
                            label: AppLocalizations.of(context).contactSupport,
                            onTap: () async {
                              _logger.warning(
                                "Backup failed for ${widget.item.file.displayName}",
                                widget.item.error,
                              );
                              await sendLogs(
                                context,
                                AppLocalizations.of(context).contactSupport,
                                "support@ente.com",
                                postShare: () {},
                              );
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                          ButtonComponent(
                            label: AppLocalizations.of(context).ok,
                            variant: ButtonComponentVariant.secondary,
                            onTap: () async {
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (hasError) const SizedBox(width: 12),
            SizedBox(
              height: 48,
              width: 48,
              child: Center(
                child: switch (widget.item.status) {
                  BackupItemStatus.uploading => SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      color: colorScheme.primary700,
                    ),
                  ),
                  BackupItemStatus.uploaded => const SizedBox(
                    width: 24,
                    height: 24,
                    child: Icon(Icons.check, color: Color(0xFF00B33C)),
                  ),
                  BackupItemStatus.inQueue => SizedBox(
                    width: 24,
                    height: 24,
                    child: Icon(
                      Icons.history,
                      color: Theme.of(context).brightness == Brightness.light
                          ? const Color.fromRGBO(0, 0, 0, .6)
                          : const Color.fromRGBO(255, 255, 255, .6),
                    ),
                  ),
                  BackupItemStatus.retry => IconButton(
                    icon: const Icon(Icons.sync, color: Color(0xFFFDB816)),
                    onPressed: () async {
                      await FileUploader.instance.upload(
                        widget.item.file,
                        widget.item.collectionID,
                      );
                    },
                  ),
                  BackupItemStatus.inBackground => SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      color: Theme.of(context).brightness == Brightness.light
                          ? const Color.fromRGBO(0, 0, 0, .6)
                          : const Color.fromRGBO(255, 255, 255, .6),
                    ),
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
