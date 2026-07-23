import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:figma_squircle/figma_squircle.dart";
import "package:flutter/material.dart";
import "package:photos/events/event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/recent_searches.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/no_thumbnail_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/search/result/go_to_map_widget.dart";
import "package:photos/ui/viewer/search/result/search_result_page.dart";
import "package:photos/ui/viewer/search/search_map_navigation.dart";
import "package:photos/ui/viewer/search/search_section_cta.dart";
import "package:photos/ui/viewer/search_tab/search_tab_horizontal_scroll.dart";
import "package:photos/ui/viewer/search_tab/section_header.dart";

class LocationsSection extends StatefulWidget {
  final List<GenericSearchResult> locationsSearchResults;
  final int resultLimit;

  const LocationsSection(
    this.locationsSearchResults, {
    super.key,
    required this.resultLimit,
  });

  @override
  State<LocationsSection> createState() => _LocationsSectionState();
}

class _LocationsSectionState extends State<LocationsSection> {
  late List<GenericSearchResult> _locationsSearchResults;
  final streamSubscriptions = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _locationsSearchResults = widget.locationsSearchResults;

    final streamsToListenTo = SectionType.location.sectionUpdateEvents();
    for (Stream<Event> stream in streamsToListenTo) {
      streamSubscriptions.add(
        stream.listen((event) async {
          if (!mounted) return;
          final results = await SectionType.location.getData(
            context,
            limit: widget.resultLimit + 1,
          );
          if (!mounted) return;
          _locationsSearchResults = results as List<GenericSearchResult>;
          setState(() {});
        }),
      );
    }
  }

  @override
  void dispose() {
    for (var subscriptions in streamSubscriptions) {
      subscriptions.cancel();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LocationsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _locationsSearchResults = widget.locationsSearchResults;
  }

  @override
  Widget build(BuildContext context) {
    if (_locationsSearchResults.isEmpty) {
      final colors = context.componentColors;
      return Padding(
        padding: const EdgeInsets.only(
          left: searchTabSectionHorizontalPadding,
          right: searchTabSectionHorizontalPadding,
          bottom: 20,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    SectionType.location.sectionTitle(context),
                    style: TextStyles.display3.copyWith(color: colors.textBase),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    SectionType.location.getEmptyStateText(context),
                    style: TextStyles.body.copyWith(color: colors.textLight),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const SearchSectionEmptyCTAIcon(SectionType.location),
            const GoToMap(),
          ],
        ),
      );
    } else {
      final visibleResults = _locationsSearchResults
          .take(widget.resultLimit)
          .toList(growable: false);
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              SectionType.location,
              hasMore: _locationsSearchResults.length > widget.resultLimit,
            ),
            const SizedBox(height: 4),
            SearchTabHorizontalRow(
              spacing: 10,
              children: [
                const GoToMapTile(),
                for (final locationSearchResult in visibleResults)
                  LocationRecommendation(locationSearchResult),
              ],
            ),
          ],
        ),
      );
    }
  }
}

class LocationRecommendation extends StatelessWidget {
  static const width = 108.0;
  static const outerCornerRadius = 20.0;
  static const cornerSmoothing = 1.0;
  static const sideOfThumbnail = 108.0;
  final GenericSearchResult locationSearchResult;
  const LocationRecommendation(this.locationSearchResult, {super.key});

  @override
  Widget build(BuildContext context) {
    final heroTag =
        locationSearchResult.heroTag() +
        (locationSearchResult.previewThumbnail()?.tag ?? "");
    final textTheme = getEnteTextTheme(context);
    return GestureDetector(
      onTap: () {
        RecentSearches().add(locationSearchResult.name());
        if (locationSearchResult.onResultTap != null) {
          locationSearchResult.onResultTap!(context);
        } else {
          routeToPage(context, SearchResultPage(locationSearchResult));
        }
      },
      child: RepaintBoundary(
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipSmoothRect(
                    radius: SmoothBorderRadius(
                      cornerRadius: outerCornerRadius,
                      cornerSmoothing: cornerSmoothing,
                    ),
                    child: SizedBox(
                      width: sideOfThumbnail,
                      height: sideOfThumbnail,
                      child: locationSearchResult.previewThumbnail() != null
                          ? Hero(
                              tag: heroTag,
                              child: ThumbnailWidget(
                                locationSearchResult.previewThumbnail()!,
                                shouldShowSyncStatus: false,
                                shouldShowFavoriteIcon: false,
                              ),
                            )
                          : const NoThumbnailWidget(),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        ClipOval(
                          child: Container(
                            color: const Color.fromRGBO(0, 0, 0, 0.6),
                            width: 15,
                            height: 15,
                          ),
                        ),
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              width: 0.5,
                              color: strokeSolidMutedLight,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.location_on_sharp,
                          color: Colors.white,
                          size: 11,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                locationSearchResult.name(),
                style: TextStyles.body.copyWith(color: textTheme.body.color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GoToMapTile extends StatelessWidget {
  const GoToMapTile({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final mapTileAsset = EnteTheme.isDark(context)
        ? "assets/search_map_tile_dark.png"
        : "assets/search_map_tile_light.png";
    return GestureDetector(
      onTap: () => openSearchMap(context),
      child: SizedBox(
        width: LocationRecommendation.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipSmoothRect(
              radius: SmoothBorderRadius(
                cornerRadius: LocationRecommendation.outerCornerRadius,
                cornerSmoothing: LocationRecommendation.cornerSmoothing,
              ),
              child: Image.asset(
                mapTileAsset,
                width: LocationRecommendation.sideOfThumbnail,
                height: LocationRecommendation.sideOfThumbnail,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).yourMap,
              style: TextStyles.body.copyWith(color: textTheme.body.color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
