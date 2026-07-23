import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/events/people_sort_order_change_event.dart";
import "package:photos/events/tab_changed_event.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/services/search_service.dart";
import "package:photos/ui/viewer/search_tab/search_tab_preview_limits.dart";

class AllSectionsExamplesData {
  final List<List<SearchResult>> sectionResults;
  final bool hasAnySearchableFiles;

  const AllSectionsExamplesData({
    required this.sectionResults,
    required this.hasAnySearchableFiles,
  });
}

class AllSectionsExamplesProvider extends StatefulWidget {
  final Widget child;
  final SearchTabPreviewLimits previewLimits;

  const AllSectionsExamplesProvider({
    super.key,
    required this.child,
    required this.previewLimits,
  });

  @override
  State<AllSectionsExamplesProvider> createState() =>
      _AllSectionsExamplesProviderState();
}

class _AllSectionsExamplesProviderState
    extends State<AllSectionsExamplesProvider> {
  //Some section results in [allSectionsExamplesFuture] can be out of sync
  //with what is displayed on UI. This happens when some section is
  //independently listening to some set of events and is rebuilt. Sections
  //can listen to a list of events and rebuild (see sectionUpdateEvents()
  //in search_types.dart) and new results will not reflect in
  //[allSectionsExamplesFuture] unless reloadAllSections() is called.
  Future<AllSectionsExamplesData> allSectionsExamplesFuture = Future.value(
    const AllSectionsExamplesData(
      sectionResults: [],
      hasAnySearchableFiles: false,
    ),
  );

  late StreamSubscription<FilesUpdatedEvent> _filesUpdatedEvent;
  late StreamSubscription<PeopleChangedEvent> _onPeopleChangedEvent;
  late StreamSubscription<PeopleSortOrderChangeEvent> _peopleSortChangedEvent;
  late StreamSubscription<TabChangedEvent> _tabChangeEvent;
  bool hasPendingUpdate = false;
  bool isOnSearchTab = false;
  bool _firstLoadInProgressOrComplete = false;
  final _logger = Logger("AllSectionsExamplesProvider");
  static const _initialLoadDelay = Duration(seconds: 30);
  Timer? _initialLoadTimer;

  final _debouncer = Debouncer(
    const Duration(seconds: 3),
    executionInterval: const Duration(seconds: 12),
    leading: true,
  );

  @override
  void initState() {
    super.initState();
    //add all common events for all search sections to reload to here.
    _filesUpdatedEvent = Bus.instance.on<FilesUpdatedEvent>().listen((event) {
      onDataUpdate();
    });
    _onPeopleChangedEvent = Bus.instance.on<PeopleChangedEvent>().listen((
      event,
    ) {
      onDataUpdate();
    });
    _peopleSortChangedEvent = Bus.instance
        .on<PeopleSortOrderChangeEvent>()
        .listen((event) {
          onDataUpdate();
        });
    _tabChangeEvent = Bus.instance.on<TabChangedEvent>().listen((event) {
      if (event.source == TabChangedEventSource.pageView &&
          event.selectedIndex == 3) {
        isOnSearchTab = true;
        _cancelInitialLoadTimer();
        if (hasPendingUpdate || !_firstLoadInProgressOrComplete) {
          hasPendingUpdate = false;
          reloadAllSections();
        }
      } else {
        isOnSearchTab = false;
      }
    });

    _initialLoadTimer = Timer(_initialLoadDelay, () {
      if (!_firstLoadInProgressOrComplete) {
        reloadAllSections();
      }
    });
  }

  void onDataUpdate() {
    if (!isOnSearchTab) {
      if (kDebugMode) {
        _logger.info('Skip reload till user clicks on search tab');
      }
      hasPendingUpdate = true;
    } else {
      hasPendingUpdate = false;
      reloadAllSections();
    }
  }

  void reloadAllSections() {
    _firstLoadInProgressOrComplete = true;
    _logger.info('queue reload all sections');
    _debouncer.run(() async {
      setState(() {
        _logger.info("'_debounceTimer: reloading all sections in search tab");
        final allSectionsExamples = <Future<List<SearchResult>>>[];
        final hasAnySearchableFilesFuture = SearchService.instance
            .hasAnyFilesForSearch();
        for (SectionType sectionType in SectionType.values) {
          // Albums moved to the Albums tab. Contacts and file types render as
          // lazy sections in Search so they do not block the section preload.
          if (sectionType == SectionType.contacts ||
              sectionType == SectionType.album ||
              sectionType == SectionType.fileTypesAndExtension) {
            allSectionsExamples.add(Future.value([]));
          } else {
            allSectionsExamples.add(
              sectionType.getData(context, limit: _fetchLimitFor(sectionType)),
            );
          }
        }
        try {
          allSectionsExamplesFuture = () async {
            final sectionResults = await Future.wait<List<SearchResult>>(
              allSectionsExamples,
              eagerError: false,
            );
            final hasAnySearchableFiles = await hasAnySearchableFilesFuture;
            return AllSectionsExamplesData(
              sectionResults: sectionResults,
              hasAnySearchableFiles: hasAnySearchableFiles,
            );
          }();
        } catch (e) {
          _logger.severe("Error reloading all sections: $e");
        }
      });
    });
  }

  void _cancelInitialLoadTimer() {
    _initialLoadTimer?.cancel();
    _initialLoadTimer = null;
  }

  int _fetchLimitFor(SectionType sectionType) {
    return switch (sectionType) {
      SectionType.face => widget.previewLimits.faceFetchLimit,
      SectionType.magic => widget.previewLimits.magicFetchLimit,
      SectionType.location => widget.previewLimits.locationFetchLimit,
      _ => 0,
    };
  }

  @override
  void dispose() {
    _onPeopleChangedEvent.cancel();
    _filesUpdatedEvent.cancel();
    _peopleSortChangedEvent.cancel();
    _tabChangeEvent.cancel();
    _cancelInitialLoadTimer();
    _debouncer.cancelDebounceTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InheritedAllSectionsExamples(
      allSectionsExamplesFuture,
      _debouncer.debounceActiveNotifier,
      child: widget.child,
    );
  }
}

class InheritedAllSectionsExamples extends InheritedWidget {
  final Future<AllSectionsExamplesData> allSectionsExamplesFuture;
  final ValueNotifier<bool> isDebouncingNotifier;
  const InheritedAllSectionsExamples(
    this.allSectionsExamplesFuture,
    this.isDebouncingNotifier, {
    super.key,
    required super.child,
  });

  static InheritedAllSectionsExamples of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InheritedAllSectionsExamples>()!;
  }

  @override
  bool updateShouldNotify(covariant InheritedAllSectionsExamples oldWidget) {
    return !identical(
      oldWidget.allSectionsExamplesFuture,
      allSectionsExamplesFuture,
    );
  }
}
