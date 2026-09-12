import "dart:async";
import "dart:math";
import "dart:typed_data";

import "package:collection/collection.dart";
import 'package:flutter/material.dart';
import "package:flutter_animate/flutter_animate.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/offline_files_db.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/events/diff_sync_complete_event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/events/memories_changed_event.dart";
import "package:photos/events/memories_setting_changed.dart";
import "package:photos/events/memory_seen_event.dart";
import "package:photos/events/ml_consent_changed_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/models/memory_lane/memory_lane_models.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/memory_lane/memory_lane_service.dart";
import "package:photos/ui/home/memories/all_memories_page.dart";
import "package:photos/ui/home/memories/crafting_memories_card.dart";
import 'package:photos/ui/home/memories/memory_card.dart';
import "package:photos/ui/home/memories/memory_card_constants.dart";
import "package:photos/ui/home/memories/memory_cover_util.dart";
import "package:photos/ui/home/memories/memory_lane_card.dart";
import "package:photos/ui/home/memories/memory_video_prefetcher.dart";

class MemoryCardWrapper {
  final String id;
  final Widget Function() widget;

  const MemoryCardWrapper({required this.id, required this.widget});
}

class MemoriesStripWidget extends StatefulWidget {
  const MemoriesStripWidget({super.key});

  @override
  State<MemoriesStripWidget> createState() => _MemoriesStripWidgetState();
}

class _MemoriesStripWidgetState extends State<MemoriesStripWidget> {
  late StreamSubscription<MemoriesSettingChanged> _memoriesSettingSubscription;
  late StreamSubscription<MemoriesChangedEvent> _memoriesChangedSubscription;
  late StreamSubscription<MemorySeenEvent> _memorySeenSubscription;
  late StreamSubscription<MLConsentChangedEvent> _mlConsentChangedSubscription;
  late StreamSubscription<PeopleChangedEvent> _peopleChangedSubscription;
  late StreamSubscription<LocalPhotosUpdatedEvent>
  _localPhotosUpdatedSubscription;
  late StreamSubscription<CollectionUpdatedEvent>
  _collectionUpdatedSubscription;
  late StreamSubscription<DiffSyncCompleteEvent> _diffSyncCompleteSubscription;
  late double _cardWidth;

  // Delay cover warming past startup; generations invalidate stale work.
  Timer? _warmTimer;
  int _warmGeneration = 0;
  int _fetchMemoriesGeneration = 0;
  String? _lastWarmSignature;
  MemoryLanePersonTimeline? _memoryLane;
  Uint8List? _oldestMemoryLaneFace;
  Uint8List? _newestMemoryLaneFace;
  PersonEntity? _memoryLanePerson;
  final _videoPrefetcher = MemoryVideoPrefetcher();
  final _scrollController = ScrollController();
  bool _shouldShowCraftingMemories = false;
  List<SmartMemory> _memories = [];
  final _emptyMemoriesLoaded = Completer<void>();
  late final Future<void> _cardDataLoaded;

  @override
  void initState() {
    super.initState();
    _cardDataLoaded = Future.wait<void>([
      Future.any<void>([
        Future.wait<void>([_fetchMemories(), _fetchMemoryLane()]),
        _emptyMemoriesLoaded.future,
      ]),
      _fetchCraftingMemoriesShouldShow(),
    ]);

    _memoriesSettingSubscription = Bus.instance
        .on<MemoriesSettingChanged>()
        .listen((_) => _fetchMemories());
    _memoriesChangedSubscription = Bus.instance
        .on<MemoriesChangedEvent>()
        .listen((_) => _fetchMemories());
    _memorySeenSubscription = Bus.instance.on<MemorySeenEvent>().listen(
      (_) => _fetchMemories(),
    );
    _mlConsentChangedSubscription = Bus.instance
        .on<MLConsentChangedEvent>()
        .listen(_onMLConsentChanged);
    _peopleChangedSubscription = Bus.instance.on<PeopleChangedEvent>().listen(
      _onPeopleChanged,
    );
    _localPhotosUpdatedSubscription = Bus.instance
        .on<LocalPhotosUpdatedEvent>()
        .listen(_onLocalPhotosUpdated);
    _collectionUpdatedSubscription = Bus.instance
        .on<CollectionUpdatedEvent>()
        .listen(_onCollectionUpdated);
    _diffSyncCompleteSubscription = Bus.instance
        .on<DiffSyncCompleteEvent>()
        .listen((_) => _hideMemoryLaneIfFilesMissingOrHidden());
    MemoryLaneService.instance.readyPersonIds.addListener(
      _onMemoryLaneReadyTimelinesChanged,
    );
  }

  @override
  void dispose() {
    _memoriesSettingSubscription.cancel();
    _memoriesChangedSubscription.cancel();
    _memorySeenSubscription.cancel();
    _mlConsentChangedSubscription.cancel();
    _peopleChangedSubscription.cancel();
    _localPhotosUpdatedSubscription.cancel();
    _collectionUpdatedSubscription.cancel();
    _diffSyncCompleteSubscription.cancel();
    _warmTimer?.cancel();
    _videoPrefetcher.dispose();
    _scrollController.dispose();
    MemoryLaneService.instance.readyPersonIds.removeListener(
      _onMemoryLaneReadyTimelinesChanged,
    );
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    const defaultWidth = 145.011;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenWidth < screenHeight) {
      _cardWidth = min(
        screenWidth * (defaultWidth / 376.0),
        defaultWidth * 1.5,
      );
    } else {
      _cardWidth = min(screenHeight * .3, defaultWidth * 1.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!memoriesCacheService.showAnyMemories) {
      _cancelPendingWarm();
      return const SizedBox.shrink();
    }
    return FutureBuilder(
      future: _cardDataLoaded,
      builder: (context, snapshot) {
        final cardHeight = _cardWidth / kMemoryCardAspectRatio;
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(height: cardHeight + 24);
        }
        if (_memories.isEmpty) {
          return const SizedBox.shrink();
        }
        final cards = _buildCards(_memories, cardHeight);
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 10),
          child: SizedBox(
            height: cardHeight + 2,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: kMemoryCardStripGap / 2.0,
              ),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              itemBuilder: (context, i) => KeyedSubtree(
                key: ValueKey(cards[i].id),
                child: cards[i].widget(),
              ),
            ),
          ),
        ).animate().fadeIn(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCirc,
        );
      },
    );
  }

  List<SmartMemory> _sortMemories(List<SmartMemory> memories) {
    final indexedMemories = memories.indexed.sorted((a, b) {
      final aIsSeen = a.$2.memories.every((item) => item.isSeen());
      final bIsSeen = b.$2.memories.every((item) => item.isSeen());
      if (aIsSeen == bIsSeen) return a.$1.compareTo(b.$1);
      return aIsSeen ? 1 : -1;
    });

    return indexedMemories.map((entry) => entry.$2).toList();
  }

  List<MemoryCardWrapper> _buildCards(
    List<SmartMemory> memories,
    double cardHeight,
  ) {
    final memoryLane = _memoryLane;
    final memoryLanePerson = _memoryLanePerson;
    final oldestMemoryLaneFace = _oldestMemoryLaneFace;
    final newestMemoryLaneFace = _newestMemoryLaneFace;
    final hasMemoryLane =
        flagService.internalUser &&
        MemoryLaneService.instance.isFeatureEnabled &&
        memoryLane != null &&
        (memoryLane.isCluster || memoryLanePerson != null) &&
        oldestMemoryLaneFace != null &&
        newestMemoryLaneFace != null;
    final hasContent = memories.isNotEmpty || memoryLane != null;
    final cardBuilders = <MemoryCardWrapper Function(VoidCallback onTap)>[
      if (hasMemoryLane)
        (onTap) => MemoryCardWrapper(
          id: "memoryLane_${memoryLane.personId}",
          widget: () => MemoryLaneCardWidget(
            id: memoryLane.personId,
            oldestFace: oldestMemoryLaneFace,
            face: newestMemoryLaneFace,
            personName: memoryLanePerson?.data.name ?? "",
            size: Size(_cardWidth, cardHeight),
            onTap: onTap,
          ),
        ),
      for (final memory in memories)
        (onTap) => MemoryCardWrapper(
          id: memory.id,
          widget: () => MemoryCardWidget(
            memory: memory,
            width: _cardWidth,
            height: cardHeight,
            onTap: onTap,
          ),
        ),
    ];
    final cards = cardBuilders.indexed
        .map(
          (entry) => entry.$2(() async {
            await openAllMemoriesPage(
              context: context,
              allMemories: memories,
              memoryLane: hasMemoryLane ? memoryLane : null,
              memoryLanePerson: hasMemoryLane ? memoryLanePerson : null,
              initialPageIndex: entry.$1,
            );
            if (!mounted) return;
            setState(() {});
          }),
        )
        .toList();
    final memoryLaneCard = hasMemoryLane ? cards.first : null;
    final hasSeenMemoryLane =
        hasMemoryLane && localSettings.hasSeenMemoryLane(memoryLane.personId);
    return [
      if (_shouldShowCraftingMemories && hasContent)
        MemoryCardWrapper(
          id: "craftingMemories",
          widget: () => CraftingMemoriesCardWidget(
            width: cardHeight / 2,
            height: cardHeight,
            onShouldShowChanged: (shouldShow) {
              if (!mounted || shouldShow == _shouldShowCraftingMemories) {
                return;
              }
              setState(() {
                _shouldShowCraftingMemories = shouldShow;
              });
            },
          ),
        ),
      if (memoryLaneCard != null && !hasSeenMemoryLane) memoryLaneCard,
      ...cards.skip(hasMemoryLane ? 1 : 0),
      if (memoryLaneCard != null && hasSeenMemoryLane) memoryLaneCard,
    ];
  }

  Future<void> _fetchCraftingMemoriesShouldShow() async {
    _shouldShowCraftingMemories = await CraftingMemoriesCardWidget.shouldShow();
  }

  Future<void> _fetchMemories() async {
    final fetchGeneration = ++_fetchMemoriesGeneration;
    try {
      final memories = _sortMemories(await memoriesCacheService.getMemories());
      if (!mounted || fetchGeneration != _fetchMemoriesGeneration) {
        return;
      }
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      if (memories.isEmpty || !memoriesCacheService.showAnyMemories) {
        _cancelPendingWarm();
        setState(() => _memories = []);
        if (!_emptyMemoriesLoaded.isCompleted) {
          _emptyMemoriesLoaded.complete();
        }
        return;
      }
      _scheduleWarmCovers(memories);
      setState(() => _memories = memories);
    } catch (_) {
      if (mounted && fetchGeneration == _fetchMemoriesGeneration) {
        _cancelPendingWarm();
        setState(() => _memories = []);
        if (!_emptyMemoriesLoaded.isCompleted) {
          _emptyMemoriesLoaded.complete();
        }
      }
    }
  }

  void _scheduleWarmCovers(List<SmartMemory> memories) {
    final warmSignature = _warmSignature(memories);
    if (warmSignature == _lastWarmSignature) return;
    _lastWarmSignature = warmSignature;
    _warmGeneration++;
    final gen = _warmGeneration;
    _warmTimer?.cancel();
    _warmTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || gen != _warmGeneration) return;
      final itemLists = memories.map((e) => e.memories).toList(growable: false);
      _videoPrefetcher.prefetchFiles(
        itemLists
            .take(kMemoryCoverWarmCap)
            .where((items) => items.isNotEmpty)
            .map((items) => items[getNextMemoryIndex(items)].file),
        stillActive: () => mounted && gen == _warmGeneration,
        replacePending: true,
      );
      unawaited(
        warmMemoryCovers(
          itemLists,
          stillActive: () => mounted && gen == _warmGeneration,
        ),
      );
    });
  }

  String _warmSignature(List<SmartMemory> memories) {
    return memories
        .map((e) => e.memories)
        .take(kMemoryCoverWarmCap)
        .where((items) => items.isNotEmpty)
        .map((items) {
          final file = items[getNextMemoryIndex(items)].file;
          return '${file.uploadedFileID ?? ""}|'
              '${file.generatedID ?? ""}|'
              '${file.localID ?? ""}|'
              '${file.fileType.name}';
        })
        .join(',');
  }

  // Invalidate in-flight work and allow the same dataset to be scheduled again.
  void _cancelPendingWarm() {
    _warmTimer?.cancel();
    _warmTimer = null;
    _warmGeneration++;
    _lastWarmSignature = null;
    _videoPrefetcher.clearPending();
  }

  Future<void> _fetchMemoryLane() async {
    if (!flagService.internalUser) {
      return;
    }
    final timeline = await MemoryLaneService.instance
        .getScheduledMemoriesStripTimeline();
    if (timeline == null) {
      return;
    }
    final faceCrops = await MemoryLaneService.instance
        .getOldestAndNewestFaceCrops(timeline);
    PersonEntity? person;
    if (!timeline.isCluster) {
      person = await PersonService.instance.getPerson(timeline.personId);
    }
    if (!mounted || faceCrops == null || !hasGrantedMLConsent) {
      return;
    }
    _memoryLane = timeline;
    _oldestMemoryLaneFace = faceCrops.oldest;
    _newestMemoryLaneFace = faceCrops.newest;
    _memoryLanePerson = person;
  }

  void _hideMemoryLane() {
    setState(() {
      _memoryLane = null;
      _oldestMemoryLaneFace = null;
      _newestMemoryLaneFace = null;
      _memoryLanePerson = null;
    });
  }

  void _onMLConsentChanged(MLConsentChangedEvent event) {
    if (event.enabled || !mounted) {
      return;
    }
    _hideMemoryLane();
  }

  Future<void> _onPeopleChanged(PeopleChangedEvent event) async {
    final memoryLane = _memoryLane;
    if (!mounted ||
        memoryLane == null ||
        event.type == PeopleEventType.syncDone) {
      return;
    }
    if (event.persons == null && (event.person?.data.isIgnored ?? false)) {
      // MemoryLaneService invalidates these timelines and updates readyPersonIds.
      return;
    }
    var shouldHide = false;
    var memoryLanePerson = _memoryLanePerson;
    if (memoryLane.isCluster) {
      if (!isLocalGalleryMode) {
        final assignedClusterIDs = <String>{
          ...?event.newClusterIDs,
          ...?event.person?.data.assigned.map((cluster) => cluster.id),
          ...?event.persons
              ?.expand((person) => person.data.assigned)
              .map((cluster) => cluster.id),
          if (event.type == PeopleEventType.addedClusterToPerson) event.source,
        };
        shouldHide = assignedClusterIDs.contains(memoryLane.personId);
      }
    } else {
      final person = await PersonService.instance.getPerson(
        memoryLane.personId,
      );
      shouldHide =
          person == null ||
          person.data.isIgnored ||
          person.data.hideFromMemories;
      memoryLanePerson = person;
    }
    if (!shouldHide) {
      final mlDataDB = isLocalGalleryMode
          ? MLDataDB.localGalleryInstance
          : MLDataDB.instance;
      final faceIDs = memoryLane.isCluster
          ? (await mlDataDB.getFaceIDsForCluster(memoryLane.personId)).toSet()
          : await mlDataDB.getFaceIDsForPerson(memoryLane.personId);
      shouldHide = memoryLane.entries.any(
        (entry) => !faceIDs.contains(entry.faceId),
      );
    }
    if (!mounted || _memoryLane != memoryLane) {
      return;
    }
    if (!shouldHide) {
      if (_memoryLanePerson != memoryLanePerson) {
        setState(() {
          _memoryLanePerson = memoryLanePerson;
        });
      }
      return;
    }
    _hideMemoryLane();
  }

  Future<void> _onLocalPhotosUpdated(LocalPhotosUpdatedEvent event) async {
    final memoryLane = _memoryLane;
    if (!mounted || memoryLane == null) {
      return;
    }
    if (event.type != EventType.hide &&
        event.type != EventType.deletedFromEverywhere &&
        event.type !=
            (isLocalGalleryMode
                ? EventType.deletedFromDevice
                : EventType.deletedFromRemote)) {
      return;
    }
    if (event.type != EventType.hide) {
      if (event.type != EventType.deletedFromRemote ||
          event.source != "syncDeleteFromRemote") {
        await _hideMemoryLaneIfFilesMissingOrHidden();
      }
      return;
    }
    final Set<int> updatedFileIds;
    if (isLocalGalleryMode) {
      final localIds = event.updatedFiles
          .map((file) => file.localID)
          .whereType<String>()
          .where((id) => id.isNotEmpty);
      updatedFileIds = (await OfflineFilesDB.instance.getLocalIntIdsForLocalIds(
        localIds,
      )).values.toSet();
    } else {
      updatedFileIds = event.updatedFiles
          .map((file) => file.uploadedFileID)
          .whereType<int>()
          .toSet();
    }
    if (!mounted ||
        _memoryLane != memoryLane ||
        !memoryLane.entries.any(
          (entry) => updatedFileIds.contains(entry.fileId),
        )) {
      return;
    }
    _hideMemoryLane();
  }

  // TODO: Recompute the timeline instead of hiding the card.
  Future<void> _onCollectionUpdated(CollectionUpdatedEvent event) async {
    final memoryLane = _memoryLane;
    if (!mounted || memoryLane == null || isLocalGalleryMode) {
      return;
    }
    if (event.type == EventType.hide && event.collectionID != null) {
      final filesByCollection = await FilesDB.instance
          .getAllFilesGroupByCollectionID(
            memoryLane.entries.map((entry) => entry.fileId).toList(),
          );
      if (!mounted || _memoryLane != memoryLane) {
        return;
      }
      if (filesByCollection.containsKey(event.collectionID)) {
        _hideMemoryLane();
      }
    } else if (event.type == EventType.deletedFromRemote &&
        event.updatedFiles.isEmpty) {
      await _hideMemoryLaneIfFilesMissingOrHidden();
    }
  }

  Future<void> _hideMemoryLaneIfFilesMissingOrHidden() async {
    final memoryLane = _memoryLane;
    if (!mounted || memoryLane == null) {
      return;
    }
    final files = await MemoryLaneService.instance.getTimelineFiles(
      memoryLane.entries.map((entry) => entry.fileId),
    );
    var shouldHide = memoryLane.entries.any(
      (entry) => !files.containsKey(entry.fileId),
    );
    if (!shouldHide && !isLocalGalleryMode) {
      final hiddenCollectionIds = CollectionsService.instance
          .getHiddenCollectionIds();
      if (hiddenCollectionIds.isNotEmpty) {
        final filesByCollection = await FilesDB.instance
            .getAllFilesGroupByCollectionID(
              memoryLane.entries.map((entry) => entry.fileId).toList(),
            );
        shouldHide = filesByCollection.keys.any(hiddenCollectionIds.contains);
      }
    }
    if (!mounted || _memoryLane != memoryLane || !shouldHide) {
      return;
    }
    _hideMemoryLane();
  }

  void _onMemoryLaneReadyTimelinesChanged() {
    final memoryLane = _memoryLane;
    if (memoryLane == null ||
        MemoryLaneService.instance.readyPersonIds.value.contains(
          memoryLane.personId,
        )) {
      return;
    }
    if (!mounted) {
      return;
    }
    _hideMemoryLane();
  }
}
