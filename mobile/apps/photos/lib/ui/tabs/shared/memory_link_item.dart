import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/db/files_db.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/ui/components/collection_share_badge.dart";
import "package:photos/ui/viewer/file/no_thumbnail_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class MemoryLinkAlbumItem extends StatelessWidget {
  static const _thumbSize = 52.0;
  static const _cornerRadius = 12.0;
  static const _rowHeight = 68.0;
  static const _cardRadius = 20.0;

  static const heroTagPrefix = "memory_link";
  final String title;
  final int? fileCount;
  final int? previewUploadedFileID;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MemoryLinkAlbumItem({
    super.key,
    required this.title,
    this.fileCount,
    this.previewUploadedFileID,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  Future<EnteFile?> _loadPreviewFile() async {
    final uploadedID = previewUploadedFileID;
    if (uploadedID != null) {
      return FilesDB.instance.getAnyUploadedFile(uploadedID);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        curve: Curves.easeOut,
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: _rowHeight),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.fillLight,
          border: Border.all(
            color: isSelected ? colors.strokeDark : colors.fillLight,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(_cardRadius)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              flex: 6,
              child: Row(
                children: [
                  SizedBox(
                    width: _thumbSize,
                    height: _thumbSize,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        FutureBuilder<EnteFile?>(
                          future: _loadPreviewFile(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data != null) {
                              final String heroTag =
                                  heroTagPrefix + snapshot.data!.tag;
                              return Hero(
                                tag: heroTag,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    _cornerRadius,
                                  ),
                                  child: ThumbnailWidget(
                                    snapshot.data!,
                                    key: ValueKey(heroTag),
                                  ),
                                ),
                              );
                            }
                            return const NoThumbnailWidget(
                              addBorder: false,
                              borderRadius: _cornerRadius,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const CollectionLinkBadge(
                              variant: CollectionShareBadgeVariant.outlined,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(
                            context,
                          ).itemCount(count: fileCount ?? 0),
                          style: TextStyles.mini.copyWith(
                            color: colors.textLight,
                          ),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              flex: 1,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: isSelected
                    ? const Padding(
                        key: ValueKey("selected"),
                        padding: EdgeInsets.only(right: 8),
                        child: CollectionSelectedBadge(),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
