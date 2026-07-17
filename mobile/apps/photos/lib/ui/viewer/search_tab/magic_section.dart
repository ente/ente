import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:figma_squircle/figma_squircle.dart";
import "package:flutter/material.dart";
import "package:photos/events/event.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/recent_searches.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/no_thumbnail_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/search_tab/search_tab_horizontal_scroll.dart";
import "package:photos/ui/viewer/search_tab/section_header.dart";

class MagicSection extends StatefulWidget {
  final List<GenericSearchResult> magicSearchResults;
  final int resultLimit;

  const MagicSection(
    this.magicSearchResults, {
    super.key,
    required this.resultLimit,
  });

  @override
  State<MagicSection> createState() => _MagicSectionState();
}

class _MagicSectionState extends State<MagicSection> {
  late List<GenericSearchResult> _magicSearchResults;
  final streamSubscriptions = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _magicSearchResults = widget.magicSearchResults;

    final streamsToListenTo = SectionType.magic.sectionUpdateEvents();
    for (Stream<Event> stream in streamsToListenTo) {
      streamSubscriptions.add(
        stream.listen((event) async {
          if (!mounted) return;
          final results = await SectionType.magic.getData(
            context,
            limit: widget.resultLimit + 1,
          );
          if (!mounted) return;
          _magicSearchResults = results as List<GenericSearchResult>;
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
  void didUpdateWidget(covariant MagicSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.magicSearchResults.isNotEmpty) {
      _magicSearchResults = widget.magicSearchResults;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_magicSearchResults.isEmpty) {
      // final textTheme = getEnteTextTheme(context);
      // return Padding(
      //   padding: const EdgeInsets.only(left: 12, right: 8),
      //   child: Row(
      //     children: [
      //       Expanded(
      //         child: Column(
      //           crossAxisAlignment: CrossAxisAlignment.start,
      //           children: [
      //             Text(
      //               SectionType.magic.sectionTitle(context),
      //               style: textTheme.largeBold,
      //             ),
      //             const SizedBox(height: 24),
      //             Padding(
      //               padding: const EdgeInsets.only(left: 4),
      //               child: Text(
      //                 SectionType.magic.getEmptyStateText(context),
      //                 style: textTheme.smallMuted,
      //               ),
      //             ),
      //           ],
      //         ),
      //       ),
      //       const SizedBox(width: 8),
      //       const SearchSectionEmptyCTAIcon(SectionType.magic),
      //     ],
      //   ),
      // );
      return const SizedBox.shrink();
    } else {
      final visibleResults = _magicSearchResults
          .take(widget.resultLimit)
          .toList(growable: false);
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              SectionType.magic,
              hasMore: _magicSearchResults.length > widget.resultLimit,
            ),
            const SizedBox(height: 4),
            SearchTabHorizontalRow(
              spacing: 10,
              children: [
                for (final magicSearchResult in visibleResults)
                  MagicRecommendation(magicSearchResult),
              ],
            ),
          ],
        ),
      );
    }
  }
}

class MagicRecommendation extends StatelessWidget {
  static const _width = 108.0;
  static const _thumbnailSize = 108.0;
  static const _cornerRadius = 20.0;
  static const _cornerSmoothing = 1.0;
  final GenericSearchResult magicSearchResult;
  const MagicRecommendation(this.magicSearchResult, {super.key});

  @override
  Widget build(BuildContext context) {
    final heroTag =
        magicSearchResult.heroTag() +
        (magicSearchResult.previewThumbnail()?.tag ?? "");
    final textTheme = getEnteTextTheme(context);
    return GestureDetector(
      onTap: () {
        RecentSearches().add(magicSearchResult.name());

        magicSearchResult.onResultTap!(context);
      },
      child: SizedBox(
        width: _width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipSmoothRect(
              radius: SmoothBorderRadius(
                cornerRadius: _cornerRadius,
                cornerSmoothing: _cornerSmoothing,
              ),
              child: SizedBox(
                width: _thumbnailSize,
                height: _thumbnailSize,
                child: magicSearchResult.previewThumbnail() != null
                    ? Hero(
                        tag: heroTag,
                        child: ThumbnailWidget(
                          magicSearchResult.previewThumbnail()!,
                          shouldShowSyncStatus: false,
                        ),
                      )
                    : const NoThumbnailWidget(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              magicSearchResult.name(),
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
