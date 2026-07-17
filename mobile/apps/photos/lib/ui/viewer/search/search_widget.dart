import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/clear_and_unfocus_search_bar_event.dart";
import "package:photos/events/tab_changed_event.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/index_of_indexed_stack.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/services/search_service.dart";
import "package:photos/ui/viewer/search/search_suffix_icon_widget.dart";
import "package:photos/utils/pending_translation.dart";

class SearchWidget extends StatefulWidget {
  const SearchWidget({
    super.key,
    this.shouldConsumeBackNotifier,
    this.onSearchInputActiveChanged,
  });

  final ValueNotifier<bool>? shouldConsumeBackNotifier;
  final ValueChanged<bool>? onSearchInputActiveChanged;

  @override
  State<SearchWidget> createState() => SearchWidgetState();
}

class SearchWidgetState extends State<SearchWidget> {
  static final ValueNotifier<Stream<List<SearchResult>>?>
  searchResultsStreamNotifier = ValueNotifier(null);

  ///This stores the query that is being searched for. When going to other tabs
  ///when searching, this state gets disposed and when coming back to the
  ///search tab, this query is used to populate the search bar.
  static String query = "";
  //Debouncing + querying
  static final isLoading = ValueNotifier(false);
  final _searchService = SearchService.instance;
  final _debouncer = Debouncer(const Duration(milliseconds: 314));
  late FocusNode focusNode;
  StreamSubscription<TabChangedEvent>? _tabChangedEvent;
  StreamSubscription<TabDoubleTapEvent>? _tabDoubleTapEvent;
  TextEditingController textController = TextEditingController();
  String? _lastRequestedQuery;
  bool? _lastReportedSearchInputActive;
  late final StreamSubscription<ClearAndUnfocusSearchBar>
  _clearAndUnfocusSearchBar;
  late final Logger _logger = Logger("SearchWidgetState");

  @override
  void initState() {
    super.initState();
    focusNode = FocusNode();
    focusNode.addListener(() {
      if (!mounted) {
        return;
      }
      _syncSearchBackNotifier();
      _notifySearchInputActiveChanged();
      setState(() {});
    });
    _tabChangedEvent = Bus.instance.on<TabChangedEvent>().listen((event) async {
      if (!mounted) {
        return;
      }
      if (event.selectedIndex != 3) {
        focusNode.unfocus();
      }
    });
    _tabDoubleTapEvent = Bus.instance.on<TabDoubleTapEvent>().listen((
      event,
    ) async {
      debugPrint("Firing now ${event.selectedIndex}");
      if (mounted && event.selectedIndex == 3) {
        focusNode.requestFocus();
      }
    });

    textController.addListener(textControllerListener);

    //Populate the serach tab with the latest query when coming back
    //to the serach tab.
    textController.text = query;
    _syncSearchBackNotifier();

    _clearAndUnfocusSearchBar = Bus.instance
        .on<ClearAndUnfocusSearchBar>()
        .listen((event) {
          if (!mounted) {
            return;
          }
          textController.clear();
          focusNode.unfocus();
          _syncSearchBackNotifier(false);
          _notifySearchInputActiveChanged();
        });
  }

  @override
  void didUpdateWidget(covariant SearchWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shouldConsumeBackNotifier !=
        widget.shouldConsumeBackNotifier) {
      _syncSearchBackNotifier(false, oldWidget.shouldConsumeBackNotifier);
      _syncSearchBackNotifier();
    }
  }

  @override
  void dispose() {
    _syncSearchBackNotifier(false);
    _debouncer.cancelDebounceTimer();
    focusNode.dispose();
    _tabChangedEvent?.cancel();
    _tabDoubleTapEvent?.cancel();
    textController.removeListener(textControllerListener);
    textController.dispose();
    _clearAndUnfocusSearchBar.cancel();
    super.dispose();
  }

  void _syncSearchBackNotifier([
    bool? shouldConsumeBack,
    ValueNotifier<bool>? notifier,
  ]) {
    final backNotifier = notifier ?? widget.shouldConsumeBackNotifier;
    final shouldConsume =
        shouldConsumeBack ??
        (focusNode.hasFocus || textController.text.trim().isNotEmpty);
    if (backNotifier == null || backNotifier.value == shouldConsume) {
      return;
    }
    backNotifier.value = shouldConsume;
  }

  Future<void> textControllerListener() async {
    _syncSearchBackNotifier();
    _notifySearchInputActiveChanged();
    final nextQuery = textController.text.trim();
    if (nextQuery == _lastRequestedQuery) {
      return;
    }
    _lastRequestedQuery = nextQuery;
    isLoading.value = true;
    _debouncer.run(() async {
      if (mounted) {
        query = nextQuery;
        IndexOfStackNotifier().isSearchQueryEmpty = query.isEmpty;
        searchResultsStreamNotifier.value = _getSearchResultsStream(
          context,
          query,
        );
      }
    });
  }

  void _notifySearchInputActiveChanged() {
    final isSearchInputActive =
        focusNode.hasFocus || textController.text.trim().isNotEmpty;
    if (_lastReportedSearchInputActive == isSearchInputActive) {
      return;
    }
    _lastReportedSearchInputActive = isSearchInputActive;
    widget.onSearchInputActiveChanged?.call(isSearchInputActive);
  }

  @override
  Widget build(BuildContext context) {
    final componentColors = context.componentColors;
    final shouldShowClearButton =
        focusNode.hasFocus ||
        MediaQuery.viewInsetsOf(context).bottom > 0 ||
        textController.text.trim().isNotEmpty;
    return RepaintBoundary(
      child: TextInputComponent(
        controller: textController,
        focusNode: focusNode,
        hintText: pendingTranslation("Search photos, people, places..."),
        shouldUnfocusOnClearOrSubmit: true,
        prefix: HugeIcon(
          icon: HugeIcons.strokeRoundedSearch01,
          size: 18,
          color: componentColors.textLight,
        ),
        suffix: ValueListenableBuilder(
          valueListenable: isLoading,
          builder: (BuildContext context, bool isSearching, Widget? child) {
            return SearchSuffixIcon(
              isSearching,
              showClearButton: shouldShowClearButton,
            );
          },
        ),
      ),
    );
  }

  Stream<List<SearchResult>> _getSearchResultsStream(
    BuildContext context,
    String query,
  ) {
    int resultCount = 0;
    final maxResultCount = _isYearValid(query) ? 13 : 12;
    final streamController = StreamController<List<SearchResult>>();

    if (query.isEmpty) {
      return Stream<List<SearchResult>>.multi((controller) {
        controller.add([]);
        controller.close();
      });
    }

    void onResultsReceived(List<SearchResult> results) {
      streamController.sink.add(results);
      resultCount++;
      if (resultCount == maxResultCount) {
        streamController.close();
      }
      if (resultCount > maxResultCount) {
        _logger.warning(
          "More results than expected. Expected: $maxResultCount, actual: $resultCount",
        );
      }
    }

    if (_isYearValid(query)) {
      _searchService.getYearSearchResults(query).then((yearSearchResults) {
        onResultsReceived(yearSearchResults);
      });
    }

    _searchService.getHolidaySearchResults(context, query).then((
      holidayResults,
    ) {
      onResultsReceived(holidayResults);
    });

    _searchService.getFileTypeResults(context, query).then((
      fileTypeSearchResults,
    ) {
      onResultsReceived(fileTypeSearchResults);
    });

    _searchService.getCaptionAndNameResults(query).then((
      captionAndDisplayNameResult,
    ) {
      onResultsReceived(captionAndDisplayNameResult);
    });

    _searchService.getFileExtensionResults(query).then((fileExtnResult) {
      onResultsReceived(fileExtnResult);
    });

    _searchService.getLocationResults(context, query).then((locationResult) {
      onResultsReceived(locationResult);
    });

    _searchService.getAllFace(null, minClusterSize: 10).then((faceResult) {
      final List<GenericSearchResult> filteredResults = [];
      for (final result in faceResult) {
        if (result.name().toLowerCase().contains(query.toLowerCase())) {
          filteredResults.add(result);
        }
      }
      onResultsReceived(filteredResults);
    });

    _searchService.getCollectionSearchResults(query).then((collectionResults) {
      onResultsReceived(collectionResults);
    });

    _searchService.getDeviceCollectionSearchResults(query).then((
      deviceCollectionResults,
    ) {
      onResultsReceived(deviceCollectionResults);
    });

    _searchService.getMonthSearchResults(context, query).then((monthResults) {
      onResultsReceived(monthResults);
    });

    _searchService.getDateResults(context, query).then((possibleEvents) {
      onResultsReceived(possibleEvents);
    });

    _searchService.getMagicSearchResults(context, query).then((magicResults) {
      onResultsReceived(magicResults);
    });

    _searchService.getContactSearchResults(query).then((contactResults) {
      onResultsReceived(contactResults);
    });

    return streamController.stream.asBroadcastStream();
  }

  bool _isYearValid(String year) {
    final yearAsInt = int.tryParse(year); //returns null if cannot be parsed
    return yearAsInt != null && yearAsInt <= currentYear;
  }
}
