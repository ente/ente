import "dart:async" show StreamSubscription, unawaited;
import "dart:math";
import "dart:typed_data";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/foundation.dart" show kDebugMode, visibleForTesting;
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/events/event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/person.dart";
import 'package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart';
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/people/cluster_page.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/file_face_widget.dart";
import "package:photos/ui/viewer/people/person_clusters_page.dart";
import "package:photos/ui/viewer/people/review_suggestion_changes.dart";
import "package:photos/ui/viewer/people/save_or_edit_person.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";

class SuggestionUserFeedback {
  final bool accepted;
  final ClusterSuggestion suggestion;

  SuggestionUserFeedback(this.accepted, this.suggestion);
}

class PersonReviewClusterSuggestion extends StatefulWidget {
  final PersonEntity person;
  @visibleForTesting
  final Future<List<ClusterSuggestion>> Function()? loadSuggestions;
  @visibleForTesting
  final Future<void> Function(ClusterSuggestion, bool)? saveFeedback;
  @visibleForTesting
  final Future<Map<int, Uint8List?>> Function(List<EnteFile>, String)?
  generateFaceThumbnails;
  @visibleForTesting
  final Future<Object?> Function(Widget)? openPage;

  const PersonReviewClusterSuggestion(
    this.person, {
    super.key,
    this.loadSuggestions,
    this.saveFeedback,
    this.generateFaceThumbnails,
    this.openPage,
  });

  @override
  State<PersonReviewClusterSuggestion> createState() => _PersonClustersState();
}

class _PersonClustersState extends State<PersonReviewClusterSuggestion> {
  int currentSuggestionIndex = 0;
  Key futureBuilderKeySuggestions = UniqueKey();
  Key futureBuilderKeyFaceThumbnails = UniqueKey();
  bool canGiveFeedback = true;
  List<SuggestionUserFeedback> pastUserFeedback = [];
  List<ClusterSuggestion> allSuggestions = [];
  late final Logger _logger = Logger('_PersonClustersState');
  late final mlDataDB = MLDataDB.instance;

  late Future<List<ClusterSuggestion>> futureClusterSuggestions;
  late final StreamSubscription<PeopleChangedEvent> _peopleChangedEvent;
  late final StreamSubscription<FilesUpdatedEvent> _filesUpdatedEvent;
  PeopleChangedEvent? _lastReviewedEvent;
  int _suggestionLoadID = 0;
  bool _previewOpen = false;
  bool _savingFeedback = false;
  bool _loadingSuggestions = false;
  bool _suggestionsInvalidated = false;

  @override
  void initState() {
    super.initState();
    _peopleChangedEvent = Bus.instance.on<PeopleChangedEvent>().listen(
      _onSuggestionChanged,
    );
    _filesUpdatedEvent = Bus.instance.on<FilesUpdatedEvent>().listen(
      _onSuggestionChanged,
    );
    _fetchClusterSuggestions();
  }

  @override
  void dispose() {
    _suggestionLoadID++;
    _peopleChangedEvent.cancel();
    _filesUpdatedEvent.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.strings.reviewSuggestions),
        actions: [
          if (pastUserFeedback.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.undo_outlined),
              onPressed: () async {
                await _undoLastFeedback();
              },
            ),
          IconButton(
            icon: const Icon(Icons.history_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => PersonClustersPage(widget.person),
                ),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<ClusterSuggestion>>(
        key: futureBuilderKeySuggestions,
        future: futureClusterSuggestions,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            if (snapshot.data!.isEmpty) {
              return Center(
                child: Text(
                  context.strings.noSuggestionsForPerson(
                    personName: widget.person.data.name,
                  ),
                  style: getEnteTextTheme(context).largeMuted,
                ),
              );
            }

            allSuggestions = snapshot.data!;
            final numberOfDifferentSuggestions = allSuggestions.length;
            final currentSuggestion = allSuggestions[currentSuggestionIndex];
            final String clusterID = currentSuggestion.clusterIDToMerge;
            final double distance = currentSuggestion.distancePersonToCluster;
            final bool usingMean = currentSuggestion.usedOnlyMeanForSuggestion;
            final List<EnteFile> files = currentSuggestion.filesInCluster;

            final Future<Map<int, Uint8List?>> generateFacedThumbnails =
                _generateFaceThumbnails(
                  files.sublist(0, min(files.length, 6)),
                  clusterID,
                );

            return Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: GestureDetector(
                      onTap: () => _navigateToCluster(currentSuggestion),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 20,
                        ),
                        child: _buildSuggestionView(
                          clusterID,
                          distance,
                          usingMean,
                          files,
                          numberOfDifferentSuggestions,
                          generateFacedThumbnails,
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 12.0,
                      right: 12.0,
                      bottom: 48,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: context.componentColors.warning,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    Radii.button,
                                  ),
                                ),
                                child: ButtonComponent(
                                  variant:
                                      ButtonComponentVariant.tertiaryCritical,
                                  leading: const Icon(Icons.close),
                                  label: context.strings.no,
                                  onTap: () => _handleUserClusterChoice(
                                    clusterID,
                                    false,
                                    numberOfDifferentSuggestions,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              child: ButtonComponent(
                                label: context.strings.yes,
                                onTap: () => _handleUserClusterChoice(
                                  clusterID,
                                  true,
                                  numberOfDifferentSuggestions,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _saveAsAnotherPerson(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 32,
                            ),
                            child: Text(
                              context.strings.saveAsAnotherPerson,
                              style: getEnteTextTheme(context).mini.copyWith(
                                color: getEnteColorScheme(context).textMuted,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          } else if (snapshot.hasError) {
            _logger.severe(
              "Error fetching suggestions",
              snapshot.error!,
              snapshot.stackTrace,
            );
            return const Center(child: Text("Error"));
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }

  Future<void> _handleUserClusterChoice(
    String clusterID,
    bool yesOrNo,
    int numberOfSuggestions,
  ) async {
    if (!canGiveFeedback || _savingFeedback) return;
    final suggestion = allSuggestions[currentSuggestionIndex];
    _savingFeedback = true;
    canGiveFeedback = false;
    try {
      if (widget.saveFeedback != null) {
        await widget.saveFeedback!(suggestion, yesOrNo);
      } else if (yesOrNo) {
        await ClusterFeedbackService.instance.addClusterToExistingPerson(
          person: widget.person,
          clusterID: clusterID,
        );
      } else {
        await mlDataDB.captureNotPersonFeedback(
          personID: widget.person.remoteID,
          clusterID: clusterID,
        );
      }
      _notifySuggestionReviewed();
      if (!mounted) return;
      _savingFeedback = false;
      pastUserFeedback.add(SuggestionUserFeedback(yesOrNo, suggestion));
      if (_suggestionsInvalidated ||
          !yesOrNo ||
          currentSuggestionIndex + 1 >= numberOfSuggestions) {
        _reloadSuggestions();
      } else {
        setState(() {
          currentSuggestionIndex++;
          futureBuilderKeyFaceThumbnails = UniqueKey();
        });
      }
    } catch (error, stack) {
      _logger.severe("Error saving review feedback", error, stack);
      if (!mounted) return;
      _savingFeedback = false;
      if (_suggestionsInvalidated) {
        _reloadSuggestions();
      } else {
        setState(() => canGiveFeedback = true);
      }
    }
  }

  void _notifySuggestionReviewed() {
    final event = PeopleChangedEvent(
      person: widget.person,
      type: PeopleEventType.reviewedSuggestion,
      source: runtimeType.toString(),
    );
    _lastReviewedEvent = event;
    Bus.instance.fire(event);
  }

  Future<void> _saveAsAnotherPerson() async {
    if (!canGiveFeedback ||
        _savingFeedback ||
        allSuggestions.isEmpty ||
        currentSuggestionIndex >= allSuggestions.length) {
      return;
    }

    try {
      final currentSuggestion = allSuggestions[currentSuggestionIndex];
      final clusterID = currentSuggestion.clusterIDToMerge;
      final someFile = currentSuggestion.filesInCluster.first;

      final result = await _openPage<Object>(
        SaveOrEditPerson(clusterID, file: someFile, isEditing: false),
      );
      if (result != null && result != false) {
        _notifySuggestionReviewed();
      }
      if (!mounted) return;
      if (_suggestionsInvalidated) {
        _reloadSuggestions();
      } else if (result != null && result != false) {
        if (currentSuggestionIndex + 1 >= allSuggestions.length) {
          _reloadSuggestions();
        } else {
          setState(() {
            currentSuggestionIndex++;
            futureBuilderKeyFaceThumbnails = UniqueKey();
          });
        }
      }
    } catch (e, s) {
      _logger.severe("Error saving as another person", e, s);
    }
  }

  Future<T?> _openPage<T>(Widget page) async {
    _previewOpen = true;
    try {
      if (widget.openPage != null) return await widget.openPage!(page) as T?;
      return await Navigator.of(
        context,
      ).push<T>(MaterialPageRoute(builder: (_) => page));
    } finally {
      _previewOpen = false;
    }
  }

  Future<void> _navigateToCluster(ClusterSuggestion suggestion) async {
    final sortedFiles = List<EnteFile>.from(suggestion.filesInCluster)
      ..sort((a, b) => b.creationTime!.compareTo(a.creationTime!));
    await _openPage<Object>(
      ClusterPage(
        sortedFiles,
        personID: widget.person,
        clusterID: suggestion.clusterIDToMerge,
        showNamingBanner: false,
      ),
    );
    if (mounted && _suggestionsInvalidated) _reloadSuggestions();
  }

  void _onSuggestionChanged(Event event) {
    if (identical(event, _lastReviewedEvent)) return;
    if (!reviewSuggestionsAffectedBy(
      event,
      allSuggestions.skip(currentSuggestionIndex),
      previewOpen: _previewOpen,
      suggestionsLoading: _loadingSuggestions,
      personID: widget.person.remoteID,
    )) {
      return;
    }
    _suggestionsInvalidated = true;
    if (!_previewOpen && !_savingFeedback) _reloadSuggestions();
  }

  void _reloadSuggestions() {
    _suggestionsInvalidated = false;
    setState(() {
      currentSuggestionIndex = 0;
      allSuggestions = [];
      futureBuilderKeySuggestions = UniqueKey();
      futureBuilderKeyFaceThumbnails = UniqueKey();
      _fetchClusterSuggestions();
    });
  }

  void _fetchClusterSuggestions() {
    final loadID = ++_suggestionLoadID;
    _loadingSuggestions = true;
    allSuggestions = [];
    canGiveFeedback = false;
    futureClusterSuggestions =
        (widget.loadSuggestions?.call() ??
                ClusterFeedbackService.instance.getSuggestionForPerson(
                  widget.person,
                ))
            .then((suggestions) {
              if (!mounted || loadID != _suggestionLoadID) {
                return <ClusterSuggestion>[];
              }
              allSuggestions = suggestions;
              return suggestions;
            })
            .whenComplete(() {
              if (mounted && loadID == _suggestionLoadID) {
                _loadingSuggestions = false;
              }
            });
  }

  Widget _buildSuggestionView(
    String clusterID,
    double distance,
    bool usingMean,
    List<EnteFile> files,
    int numberOfSuggestions,
    Future<Map<int, Uint8List?>> generateFaceThumbnails,
  ) {
    final widgetToReturn = Column(
      key: ValueKey("cluster_id-$clusterID-files-${files.length}"),
      children: <Widget>[
        if (kDebugMode)
          Text(
            "ClusterID: $clusterID, Distance: ${distance.toStringAsFixed(3)}, usingMean: $usingMean",
            style: getEnteTextTheme(context).smallMuted,
          ),
        Text(
          "${widget.person.data.name}?",
          style: getEnteTextTheme(context).largeMuted,
        ),
        const SizedBox(height: 24),
        _buildThumbnailWidget(files, clusterID, generateFaceThumbnails),
        const SizedBox(height: 24.0),
      ],
    );
    precomputeFaceCrops();
    return widgetToReturn;
  }

  Widget _buildThumbnailWidget(
    List<EnteFile> files,
    String clusterID,
    Future<Map<int, Uint8List?>> generateFaceThumbnails,
  ) {
    return FutureBuilder<Map<int, Uint8List?>>(
      key: futureBuilderKeyFaceThumbnails,
      future: generateFaceThumbnails,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final faceThumbnails = snapshot.data!;
          canGiveFeedback = !_savingFeedback;
          return Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _buildThumbnailWidgetsRow(
                  files,
                  clusterID,
                  faceThumbnails,
                ),
              ),
              if (files.length > 3) const SizedBox(height: 12),
              if (files.length > 3)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _buildThumbnailWidgetsRow(
                    files,
                    clusterID,
                    faceThumbnails,
                    start: 3,
                  ),
                ),
            ],
          );
        } else if (snapshot.hasError) {
          return Center(child: Text(context.strings.error));
        } else {
          canGiveFeedback = false;
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }

  List<Widget> _buildThumbnailWidgetsRow(
    List<EnteFile> files,
    String cluserId,
    Map<int, Uint8List?> faceThumbnails, {
    int start = 0,
  }) {
    return List<Widget>.generate(
      min(3, max(0, files.length - start)),
      (index) => Padding(
        padding: const EdgeInsets.all(8.0),
        child: SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            children: [
              FaceThumbnailSquircleClip(
                child: FileFaceWidget(
                  files[start + index],
                  clusterID: cluserId,
                  faceCrop:
                      faceThumbnails[files[start + index].uploadedFileID!],
                ),
              ),
              if (start + index == 5 && files.length > 6)
                FaceThumbnailSquircleClip(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                    ),
                    child: Center(
                      child: Text(
                        '+${files.length - 5}',
                        style: darkTheme.textTheme.h3Bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<int, Uint8List?>> _generateFaceThumbnails(
    List<EnteFile> files,
    String clusterID,
  ) async {
    if (widget.generateFaceThumbnails != null) {
      return widget.generateFaceThumbnails!(files, clusterID);
    }
    final futures = <Future<Uint8List?>>[];
    for (final file in files) {
      futures.add(
        precomputeClusterFaceCrop(file, clusterID, useFullFile: true),
      );
    }
    final faceCropsList = await Future.wait(futures);
    final faceCrops = <int, Uint8List?>{};
    for (var i = 0; i < faceCropsList.length; i++) {
      faceCrops[files[i].uploadedFileID!] = faceCropsList[i];
    }
    return faceCrops;
  }

  void precomputeFaceCrops() {
    const precomputeSuggestions = 6;
    const maxPrecomputations = 8;
    int compCount = 0;
    if (allSuggestions.length > currentSuggestionIndex + 1) {
      outerLoop:
      for (final suggestion in allSuggestions.sublist(
        currentSuggestionIndex + 1,
        min(
          allSuggestions.length,
          currentSuggestionIndex + precomputeSuggestions,
        ),
      )) {
        final files = suggestion.filesInCluster;
        final clusterID = suggestion.clusterIDToMerge;
        final preComputesLeft = maxPrecomputations - compCount;
        final computeHere = min(files.length, min(preComputesLeft, 6));
        unawaited(
          _generateFaceThumbnails(files.sublist(0, computeHere), clusterID),
        );
        compCount += computeHere;
        if (compCount >= maxPrecomputations) {
          debugPrint('Prefetching $compCount face thumbnails for suggestions');
          break outerLoop;
        }
      }
    }
  }

  Future<void> _undoLastFeedback() async {
    if (pastUserFeedback.isNotEmpty) {
      final SuggestionUserFeedback lastFeedback = pastUserFeedback.removeLast();
      if (lastFeedback.accepted) {
        await PersonService.instance.removeClusterToPerson(
          personID: widget.person.remoteID,
          clusterID: lastFeedback.suggestion.clusterIDToMerge,
        );
      } else {
        await mlDataDB.removeNotPersonFeedback(
          personID: widget.person.remoteID,
          clusterID: lastFeedback.suggestion.clusterIDToMerge,
        );
      }
      _notifySuggestionReviewed();
      if (!mounted) return;

      futureClusterSuggestions = futureClusterSuggestions.then((list) {
        return list.sublist(currentSuggestionIndex)
          ..insert(0, lastFeedback.suggestion);
      });
      currentSuggestionIndex = 0;
      futureBuilderKeySuggestions = UniqueKey();
      futureBuilderKeyFaceThumbnails = UniqueKey();
      setState(() {});
    }
  }
}
