import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import "package:flutter_animate/flutter_animate.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/search/album_search_result.dart";
import "package:photos/models/search/device_album_search_result.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/index_of_indexed_stack.dart";
import 'package:photos/models/search/search_result.dart';
import "package:photos/models/search/search_types.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/thumbnail_list_item.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";
import "package:photos/ui/viewer/gallery/device/device_folder_page.dart";
import "package:photos/ui/viewer/search/result/search_result_widget.dart";
import "package:photos/ui/viewer/search/search_widget.dart";

///Not using StreamBuilder in this widget for rebuilding on every new event as
///StreamBuilder is not lossless. It misses some events if the stream fires too
///fast. Instead, we usi a queue to store the events and then generate the
///widgets from the queue at regular intervals.
class SearchSuggestionsWidget extends StatefulWidget {
  const SearchSuggestionsWidget({super.key});

  @override
  State<SearchSuggestionsWidget> createState() =>
      _SearchSuggestionsWidgetState();
}

class _SearchSuggestionsWidgetState extends State<SearchSuggestionsWidget> {
  Stream<List<SearchResult>>? resultsStream;
  final queueOfSearchResults = <List<SearchResult>>[];
  final Map<_SearchResultsSection, List<SearchResult>> _sectionedResults = {};
  StreamSubscription<List<SearchResult>>? subscription;
  Timer? timer;
  late final VoidCallback _searchResultsStreamNotifierListener;

  ///This is the interval at which the queue is checked for new events and
  ///the search result widgets are generated from the queue.
  static const _surfaceNewResultsInterval = 50;

  @override
  void initState() {
    super.initState();
    _searchResultsStreamNotifierListener = () {
      IndexOfStackNotifier().searchState = SearchState.searching;
      final resultsStream = SearchWidgetState.searchResultsStreamNotifier.value;

      _sectionedResults.clear();
      releaseResources();

      subscription = resultsStream!.listen(
        (searchResults) {
          //Currently, we add searchResults even if the list is empty. So we are adding
          //empty list to the queue, which will trigger rebuilds with no change in UI
          //(see [generateResultWidgetsInIntervalsFromQueue]'s setState()).
          //This is needed to clear the search results in this widget when the
          //search bar is cleared, and the event fired by the stream will be an
          //empty list. Can optimize rebuilds if there are performance issues in future.
          if (searchResults.isNotEmpty) {
            IndexOfStackNotifier().searchState = SearchState.notEmpty;
          }
          queueOfSearchResults.add(searchResults);
        },
        onDone: () {
          Future.delayed(
            const Duration(milliseconds: _surfaceNewResultsInterval + 20),
            () {
              if (_resultsCount == 0) {
                IndexOfStackNotifier().searchState = SearchState.empty;
              }
            },
          );
          SearchWidgetState.isLoading.value = false;
        },
      );

      generateResultWidgetsInIntervalsFromQueue();
    };
    SearchWidgetState.searchResultsStreamNotifier.addListener(
      _searchResultsStreamNotifierListener,
    );
  }

  void releaseResources() {
    subscription?.cancel();
    timer?.cancel();
    queueOfSearchResults.clear();
  }

  ///This method generates searchResultsWidgets from the queueOfEvents by checking
  ///every [_surfaceNewResultsInterval] if the queue is empty or not. If the
  ///queue is not empty, it generates the widgets and clears the queue and
  ///updates the UI.
  void generateResultWidgetsInIntervalsFromQueue() {
    timer = Timer.periodic(
      const Duration(milliseconds: _surfaceNewResultsInterval),
      (timer) {
        if (queueOfSearchResults.isNotEmpty) {
          for (List<SearchResult> event in queueOfSearchResults) {
            _addResultsToSections(event);
          }
          queueOfSearchResults.clear();
          setState(() {});
        }
      },
    );
  }

  @override
  void dispose() {
    releaseResources();
    SearchWidgetState.searchResultsStreamNotifier.removeListener(
      _searchResultsStreamNotifierListener,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final resultsBackground = EnteTheme.isDark(context)
        ? colorScheme.backgroundColour
        : colorScheme.backgroundElevated2;
    final sectionWidgets = _buildSectionWidgets(context);
    const bottomPadding = 124.0;
    if (_resultsCount > 0) {
      sectionWidgets.insert(
        0,
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(
            AppLocalizations.of(
              context,
            ).searchResultCount(count: _resultsCount),
            style: textTheme.smallBold.copyWith(color: colorScheme.textMuted),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: resultsBackground,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: bottomPadding),
                children: sectionWidgets,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _resultsCount {
    int count = 0;
    for (final results in _sectionedResults.values) {
      count += results.length;
    }
    return count;
  }

  void _addResultsToSections(List<SearchResult> results) {
    for (final result in results) {
      final section = _sectionForResult(result);
      _sectionedResults.putIfAbsent(section, () => <SearchResult>[]);
      _sectionedResults[section]!.add(result);
    }
  }

  List<Widget> _buildSectionWidgets(BuildContext context) {
    final widgets = <Widget>[];
    for (final section in _sectionOrder) {
      final results = _sectionedResults[section] ?? [];
      if (results.isEmpty) {
        continue;
      }
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 18));
      }
      widgets.add(
        _SearchResultsSectionWidget(
          title: _sectionTitle(context, section),
          icon: _sectionIcon(section),
          results: results,
        ),
      );
    }
    return widgets;
  }
}

class SearchResultsWidgetGenerator extends StatelessWidget {
  final SearchResult result;
  final bool showTypeLabel;
  const SearchResultsWidgetGenerator(
    this.result, {
    this.showTypeLabel = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (result is AlbumSearchResult) {
      final AlbumSearchResult albumSearchResult = result as AlbumSearchResult;
      return SearchResultWidget(
        result,
        resultCount: CollectionsService.instance.getFileCount(
          albumSearchResult.collectionWithThumbnail.collection,
        ),
        showTypeLabel: showTypeLabel,
        onResultTap: () => routeToPage(
          context,
          CollectionPage(
            albumSearchResult.collectionWithThumbnail,
            tagPrefix: result.heroTag(),
          ),
        ),
      );
    } else if (result is DeviceAlbumSearchResult) {
      final deviceResult = result as DeviceAlbumSearchResult;
      return SearchResultWidget(
        result,
        resultCount: Future.value(deviceResult.deviceCollection.count),
        showTypeLabel: showTypeLabel,
        onResultTap: () => routeToPage(
          context,
          DeviceFolderPage(deviceResult.deviceCollection),
        ),
      );
    } else if (result is GenericSearchResult) {
      return SearchResultWidget(
        result,
        showTypeLabel: showTypeLabel,
        onResultTap: (result as GenericSearchResult).onResultTap != null
            ? () => (result as GenericSearchResult).onResultTap!(context)
            : null,
      );
    } else {
      Logger('SearchResultsWidgetGenerator').info("Invalid/Unsupported value");
      return const SizedBox.shrink();
    }
  }
}

enum _SearchResultsSection {
  people,
  shared,
  albums,
  magic,
  files,
  locations,
  moments,
}

const List<_SearchResultsSection> _sectionOrder = [
  _SearchResultsSection.files,
  _SearchResultsSection.moments,
  _SearchResultsSection.albums,
  _SearchResultsSection.locations,
  _SearchResultsSection.people,
  _SearchResultsSection.shared,
  _SearchResultsSection.magic,
];

_SearchResultsSection _sectionForResult(SearchResult result) {
  switch (result.type()) {
    case ResultType.faces:
      return _SearchResultsSection.people;
    case ResultType.shared:
      return _SearchResultsSection.shared;
    case ResultType.collection:
    case ResultType.deviceCollection:
      return _SearchResultsSection.albums;
    case ResultType.magic:
      return _SearchResultsSection.magic;
    case ResultType.location:
    case ResultType.locationSuggestion:
      return _SearchResultsSection.locations;
    case ResultType.year:
    case ResultType.month:
    case ResultType.event:
      return _SearchResultsSection.moments;
    case ResultType.file:
    case ResultType.fileType:
    case ResultType.fileExtension:
    case ResultType.fileCaption:
    case ResultType.uploader:
    case ResultType.cameraMake:
    case ResultType.cameraModel:
      return _SearchResultsSection.files;
  }
}

String _sectionTitle(BuildContext context, _SearchResultsSection section) {
  switch (section) {
    case _SearchResultsSection.people:
      return AppLocalizations.of(context).people;
    case _SearchResultsSection.shared:
      return AppLocalizations.of(context).shared;
    case _SearchResultsSection.albums:
      return AppLocalizations.of(context).albums;
    case _SearchResultsSection.magic:
      return AppLocalizations.of(context).magic;
    case _SearchResultsSection.files:
      return AppLocalizations.of(context).files;
    case _SearchResultsSection.locations:
      return AppLocalizations.of(context).locations;
    case _SearchResultsSection.moments:
      return AppLocalizations.of(context).moments;
  }
}

List<List<dynamic>> _sectionIcon(_SearchResultsSection section) {
  switch (section) {
    case _SearchResultsSection.people:
      return HugeIcons.strokeRoundedUserMultiple;
    case _SearchResultsSection.shared:
      return HugeIcons.strokeRoundedShare08;
    case _SearchResultsSection.albums:
      return HugeIcons.strokeRoundedImage01;
    case _SearchResultsSection.magic:
      return HugeIcons.strokeRoundedSparkles;
    case _SearchResultsSection.files:
      return HugeIcons.strokeRoundedFile01;
    case _SearchResultsSection.locations:
      return HugeIcons.strokeRoundedMaping;
    case _SearchResultsSection.moments:
      return HugeIcons.strokeRoundedStar;
  }
}

class _SearchResultsSectionWidget extends StatelessWidget {
  final String title;
  final List<List<dynamic>> icon;
  final List<SearchResult> results;

  const _SearchResultsSectionWidget({
    required this.title,
    required this.icon,
    required this.results,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final colors = context.componentColors;
    final showTypeLabel = results.length > 1;
    final children = <Widget>[];
    for (int i = 0; i < results.length; i++) {
      final radius = BorderRadius.circular(20);
      children.add(
        Material(
          color: colorScheme.backgroundElevated,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child:
              SearchResultsWidgetGenerator(
                results[i],
                showTypeLabel: showTypeLabel,
              ).animate().fadeIn(
                duration: const Duration(milliseconds: 80),
                curve: Curves.easeIn,
              ),
        ),
      );
      if (i != results.length - 1) {
        children.add(
          const SizedBox(height: ThumbnailListItem.defaultItemSpacing),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.strokeFainter,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(6),
                child: HugeIcon(
                  icon: icon,
                  color: colorScheme.strokeBase,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyles.large.copyWith(color: colors.textBase),
              ),
            ],
          ),
        ),
        Column(children: children),
      ],
    );
  }
}
