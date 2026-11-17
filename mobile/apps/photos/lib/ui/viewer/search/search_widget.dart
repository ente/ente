import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_components/hugeicons.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/clear_and_unfocus_search_bar_event.dart";
import "package:photos/events/tab_changed_event.dart";
import "package:photos/models/home_tab.dart";
import "package:photos/models/search/index_of_indexed_stack.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/services/search_query_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/ui/viewer/search/search_suffix_icon_widget.dart";

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

  // The search widget is disposed when switching tabs. Preserve its query.
  static String query = "";
  static final isLoading = ValueNotifier(false);
  final _searchQueryService = SearchQueryService(SearchService.instance);
  final _debouncer = Debouncer(const Duration(milliseconds: 314));
  late FocusNode focusNode;
  StreamSubscription<TabChangedEvent>? _tabChangedEvent;
  StreamSubscription<TabDoubleTapEvent>? _tabDoubleTapEvent;
  TextEditingController textController = TextEditingController();
  String? _lastRequestedQuery;
  bool? _lastReportedSearchInputActive;
  late final StreamSubscription<ClearAndUnfocusSearchBar>
  _clearAndUnfocusSearchBar;

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
      if (event.selectedIndex != searchTabIndex) {
        focusNode.unfocus();
      }
    });
    _tabDoubleTapEvent = Bus.instance.on<TabDoubleTapEvent>().listen((
      event,
    ) async {
      debugPrint("Firing now ${event.selectedIndex}");
      if (mounted && event.selectedIndex == searchTabIndex) {
        focusNode.requestFocus();
      }
    });

    textController.addListener(textControllerListener);

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
        searchResultsStreamNotifier.value = _searchQueryService.search(
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
        hintText: context.strings.searchPhotosPeoplePlaces,
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
}
