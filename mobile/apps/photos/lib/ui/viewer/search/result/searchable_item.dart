import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:intl/intl.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/recent_searches.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/thumbnail_list_item.dart";
import "package:photos/ui/viewer/search/result/contact_result_page.dart";
import "package:photos/ui/viewer/search/result/search_result_page.dart";
import "package:photos/ui/viewer/search/result/search_thumbnail_widget.dart";

class SearchableItemWidget extends StatelessWidget {
  final SearchResult searchResult;
  final Future<int>? resultCount;
  final Function? onResultTap;
  const SearchableItemWidget(
    this.searchResult, {
    super.key,
    this.resultCount,
    this.onResultTap,
  });

  @override
  Widget build(BuildContext context) {
    //The "searchable_item" tag is to remove hero animation between section
    //examples and searchableItems in 'view all'. Animation should exist between
    //searchableItems and SearchResultPages, so passing the extra prefix to
    //SearchResultPage
    const additionalPrefix = "searchable_item";
    final heroTagPrefix = additionalPrefix + searchResult.heroTag();
    final colors = context.componentColors;
    final colorScheme = getEnteColorScheme(context);
    final result = searchResult;
    final bool isCluster =
        result.type() == ResultType.faces &&
        result is GenericSearchResult &&
        result.params.containsKey(kClusterParamId);

    return ThumbnailListItem(
      backgroundColor: thumbnailListItemBackgroundColor(context),
      onTap: () {
        RecentSearches().add(searchResult.name());
        if (onResultTap != null) {
          onResultTap!();
        } else {
          if (searchResult.type() == ResultType.shared) {
            routeToPage(
              context,
              ContactResultPage(searchResult, tagPrefix: additionalPrefix),
            );
          } else {
            routeToPage(
              context,
              SearchResultPage(searchResult, tagPrefix: additionalPrefix),
            );
          }
        }
      },
      leading: searchResult.type() == ResultType.shared
          ? ContactSearchThumbnailWidget(
              heroTagPrefix,
              searchResult: searchResult as GenericSearchResult,
              size: ThumbnailListItem.defaultLeadingSize,
              borderRadius: ThumbnailListItem.defaultLeadingRadius,
            )
          : SearchThumbnailWidget(
              searchResult.previewThumbnail(),
              heroTagPrefix,
              searchResult: searchResult,
              size: ThumbnailListItem.defaultLeadingSize,
              borderRadius: ThumbnailListItem.defaultLeadingRadius,
            ),
      title: isCluster
          ? const SizedBox.shrink()
          : Text(
              searchResult.name(),
              style: TextStyles.body.copyWith(color: colors.textBase),
              overflow: TextOverflow.ellipsis,
            ),
      subtitle: FutureBuilder<int>(
        future: resultCount ?? Future.value(searchResult.resultFiles().length),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data! > 0) {
            final noOfMemories = snapshot.data!;
            return Text(
              AppLocalizations.of(context).memoryCount(
                count: noOfMemories,
                formattedCount: NumberFormat().format(noOfMemories),
              ),
              style: TextStyles.mini.copyWith(color: colors.textLight),
              overflow: TextOverflow.ellipsis,
            );
          } else {
            return const SizedBox.shrink();
          }
        },
      ),
      trailing: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Icon(
          Icons.chevron_right_outlined,
          color: colorScheme.blurStrokePressed,
        ),
      ),
    );
  }
}

class SearchableItemPlaceholder extends StatelessWidget {
  static const _inviteAsset = "assets/invite_contact.svg";

  final SectionType sectionType;
  const SearchableItemPlaceholder(this.sectionType, {super.key});

  @override
  Widget build(BuildContext context) {
    if (sectionType.isCTAVisible == false) {
      return const SizedBox.shrink();
    }

    final colorScheme = getEnteColorScheme(context);
    final colors = context.componentColors;
    return ThumbnailListItem(
      backgroundColor: thumbnailListItemBackgroundColor(context),
      onTap: sectionType.ctaOnTap(context),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(
          ThumbnailListItem.defaultLeadingRadius,
        ),
        child: Container(
          color: colorScheme.fillFaint,
          child: Center(
            child: sectionType == SectionType.contacts
                ? SvgPicture.asset(_inviteAsset, width: 20, height: 20)
                : Icon(
                    sectionType.getCTAIcon(),
                    color: colorScheme.strokeMuted,
                  ),
          ),
        ),
      ),
      title: Text(
        sectionType.getCTAText(context),
        style: TextStyles.body.copyWith(color: colors.textBase),
      ),
    );
  }
}
