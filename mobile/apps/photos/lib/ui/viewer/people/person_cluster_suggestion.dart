import "dart:async" show StreamSubscription, unawaited;
import "dart:math";
import "dart:typed_data";

import "package:flutter/foundation.dart" show kDebugMode;
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/person.dart";
import 'package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart';
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/viewer/people/cluster_page.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/file_face_widget.dart";
import "package:photos/ui/viewer/people/person_clusters_page.dart";
import "package:photos/ui/viewer/people/save_or_edit_person.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";

class SuggestionUserFeedback {
  final bool accepted;
  final ClusterSuggestion suggestion;

  SuggestionUserFeedback(this.accepted, this.suggestion);
}

class PersonReviewClusterSuggestion extends StatefulWidget {
  final PersonEntity person;

  const PersonReviewClusterSuggestion(this.person, {super.key});

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

  // Declare a variable for the future
  late Future<List<ClusterSuggestion>> futureClusterSuggestions;
  StreamSubscription<PeopleChangedEvent>? _peopleChangedEvent;

  @override
  void initState() {
    super.initState();
    // Initialize the future in initState
    _fetchClusterSuggestions();
  }

  @override
  void dispose() {
    _peopleChangedEvent?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.reviewSuggestions),
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
              _peopleChangedEvent?.cancel();
              _peopleChangedEvent = null;
              return Center(
                child: Text(
                  AppLocalizations.of(
                    context,
                  ).noSuggestionsForPerson(personName: widget.person.data.name),
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

            _peopleChangedEvent?.cancel();
            _peopleChangedEvent = Bus.instance.on<PeopleChangedEvent>().listen((
              event,
            ) {
              if (event.source == clusterID.toString()) {
                if (event.type == PeopleEventType.removedFilesFromCluster) {
                  for (var updatedFile in event.relevantFiles!) {
                    files.remove(updatedFile);
                  }
                  setState(() {});
                }
                if (event.type == PeopleEventType.removedFaceFromCluster) {
                  for (final String removedFaceID in event.relevantFaceIDs!) {
                    final int fileID = getFileIdFromFaceId<int>(removedFaceID);
                    files.removeWhere((file) => file.uploadedFileID == fileID);
                  }
                  setState(() {});
                }
              }
            });

            return Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: GestureDetector(
                      onTap: () {
                        final List<EnteFile> sortedFiles = List<EnteFile>.from(
                          currentSuggestion.filesInCluster,
                        );
                        sortedFiles.sort(
                          (a, b) => b.creationTime!.compareTo(a.creationTime!),
                        );
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => ClusterPage(
                              sortedFiles,
                              personID: widget.person,
                              clusterID: clusterID,
                              showNamingBanner: false,
                            ),
                          ),
                        );
                      },
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
                              child: ButtonWidget(
                                buttonType: ButtonType.tertiaryCritical,
                                icon: Icons.close,
                                labelText: context.l10n.no,
                                buttonSize: ButtonSize.large,
                                onTap: () async => {
                                  await _handleUserClusterChoice(
                                    clusterID,
                                    false,
                                    numberOfDifferentSuggestions,
                                  ),
                                },
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              child: ButtonWidget(
                                buttonType: ButtonType.primary,
                                labelText: context.l10n.yes,
                                buttonSize: ButtonSize.large,
                                onTap: () async => {
                                  await _handleUserClusterChoice(
                                    clusterID,
                                    true,
                                    numberOfDifferentSuggestions,
                                  ),
                                },
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
                              AppLocalizations.of(context).saveAsAnotherPerson,
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
    // Perform the action based on clusterID, e.g., assignClusterToPerson or captureNotPersonFeedback
    if (!canGiveFeedback) {
      return;
    }
    // Store the feedback in case the user wants to revert
    pastUserFeedback.add(
      SuggestionUserFeedback(yesOrNo, allSuggestions[currentSuggestionIndex]),
    );
    if (yesOrNo) {
      canGiveFeedback = false;
      await ClusterFeedbackService.instance.addClusterToExistingPerson(
        person: widget.person,
        clusterID: clusterID,
      );
      // Increment the suggestion index
      if (mounted) {
        setState(() => currentSuggestionIndex++);
      }

      // Check if we need to fetch new data
      if (currentSuggestionIndex >= (numberOfSuggestions)) {
        setState(() {
          currentSuggestionIndex = 0;
          futureBuilderKeySuggestions =
              UniqueKey(); // Reset to trigger FutureBuilder
          futureBuilderKeyFaceThumbnails = UniqueKey();
          _fetchClusterSuggestions();
        });
      } else {
        futureBuilderKeyFaceThumbnails = UniqueKey();
        setState(() {});
      }
    } else {
      await _rejectSuggestion(clusterID, numberOfSuggestions);
    }
  }

  Future<void> _rejectSuggestion(
    String clusterID,
    int numberOfSuggestions,
  ) async {
    canGiveFeedback = false;
    await mlDataDB.captureNotPersonFeedback(
      personID: widget.person.remoteID,
      clusterID: clusterID,
    );
    // Recalculate the suggestions when a suggestion is rejected
    setState(() {
      currentSuggestionIndex = 0;
      futureBuilderKeySuggestions =
          UniqueKey(); // Reset to trigger FutureBuilder
      futureBuilderKeyFaceThumbnails = UniqueKey();
      _fetchClusterSuggestions();
    });
  }

  Future<void> _saveAsAnotherPerson() async {
    if (!canGiveFeedback ||
        allSuggestions.isEmpty ||
        currentSuggestionIndex >= allSuggestions.length) {
      return;
    }

    try {
      final currentSuggestion = allSuggestions[currentSuggestionIndex];
      final clusterID = currentSuggestion.clusterIDToMerge;
      final someFile = currentSuggestion.filesInCluster.first;

      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              SaveOrEditPerson(clusterID, file: someFile, isEditing: false),
        ),
      );
      if (result == null || result == false) {
        return;
      }
      if (mounted) {
        setState(() => currentSuggestionIndex++);
      }
      final numberOfSuggestions = allSuggestions.length;
      if (currentSuggestionIndex >= numberOfSuggestions) {
        setState(() {
          currentSuggestionIndex = 0;
          futureBuilderKeySuggestions = UniqueKey();
          futureBuilderKeyFaceThumbnails = UniqueKey();
          _fetchClusterSuggestions();
        });
      } else {
        futureBuilderKeyFaceThumbnails = UniqueKey();
        setState(() {});
      }
    } catch (e, s) {
      _logger.severe("Error saving as another person", e, s);
    }
  }

  // Method to fetch cluster suggestions
  void _fetchClusterSuggestions() {
    debugPrint("Fetching suggestions for ${widget.person.data.name}");
    futureClusterSuggestions = ClusterFeedbackService.instance
        .getSuggestionForPerson(widget.person);
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
    // Precompute face thumbnails for next suggestions, in case there are
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
          canGiveFeedback = true;
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
          // log the error
          return Center(child: Text(AppLocalizations.of(context).error));
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
