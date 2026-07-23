import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/file.dart';
import "package:photos/services/collections_service.dart";
import "package:photos/ui/components/collection_share_badge.dart";
import "package:photos/ui/viewer/file/no_thumbnail_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class QuickLinkAlbumItem extends StatelessWidget {
  static const _thumbSize = 52.0;
  static const _cornerRadius = 12.0;
  static const _rowHeight = 68.0;
  static const _cardRadius = 20.0;

  final Collection c;
  static const heroTagPrefix = "outgoing_collection";
  final List<Collection> selectedQuickLinks;

  const QuickLinkAlbumItem({
    super.key,
    required this.c,
    this.selectedQuickLinks = const [],
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = selectedQuickLinks.contains(c);
    final colors = context.componentColors;

    return AnimatedContainer(
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
                        future: CollectionsService.instance.getCover(c),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
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
                          } else {
                            return const NoThumbnailWidget(
                              addBorder: false,
                              borderRadius: _cornerRadius,
                            );
                          }
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
                              c.displayName,
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
                      FutureBuilder<int>(
                        future: CollectionsService.instance.getFileCount(c),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return Text(
                              AppLocalizations.of(
                                context,
                              ).itemCount(count: snapshot.data!),
                              style: TextStyles.mini.copyWith(
                                color: colors.textLight,
                              ),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            );
                          }
                          return Text(
                            "",
                            style: TextStyles.mini.copyWith(
                              color: colors.textLight,
                            ),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
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
    );
  }
}
