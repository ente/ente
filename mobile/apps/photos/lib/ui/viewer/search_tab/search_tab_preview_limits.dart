import "dart:math" as math;

import "package:photos/ui/viewer/search_tab/search_tab_horizontal_scroll.dart";

class SearchTabPreviewLimits {
  const SearchTabPreviewLimits({
    required this.faceResults,
    required this.magicResults,
    required this.locationResults,
    required this.contactResults,
    required this.ritualResults,
  });

  static const _extraItems = 4;
  static const _standardPreviewItemExtent = 118.0;
  static const _contactPreviewItemExtent = 104.0;
  static const _ritualPreviewItemExtent = 177.5;
  static const _fixedLocationTiles = 1;
  static const _fixedContactTiles = 1;
  static const _fixedRitualTiles = 1;

  final int faceResults;
  final int magicResults;
  final int locationResults;
  final int contactResults;
  final int ritualResults;

  int get faceFetchLimit => faceResults + 1;
  int get magicFetchLimit => magicResults + 1;
  int get locationFetchLimit => locationResults + 1;

  static SearchTabPreviewLimits forWidth(double width) {
    final rowWidth = width - (searchTabSectionHorizontalPadding * 2);
    final standardLimit = _limitForRow(
      rowWidth: rowWidth,
      itemExtent: _standardPreviewItemExtent,
    );

    return SearchTabPreviewLimits(
      faceResults: standardLimit,
      magicResults: standardLimit,
      locationResults: standardLimit - _fixedLocationTiles,
      contactResults:
          _limitForRow(
            rowWidth: rowWidth,
            itemExtent: _contactPreviewItemExtent,
          ) -
          _fixedContactTiles,
      ritualResults:
          _limitForRow(
            rowWidth: rowWidth,
            itemExtent: _ritualPreviewItemExtent,
          ) -
          _fixedRitualTiles,
    );
  }

  static int _limitForRow({
    required double rowWidth,
    required double itemExtent,
  }) {
    final visibleItems = (rowWidth / itemExtent).ceil();
    return math.max(1, visibleItems) + _extraItems;
  }
}
