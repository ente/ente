import "dart:async";
import "dart:typed_data";

import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/foundation.dart" show kDebugMode;
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/offline_files_db.dart";
import "package:photos/events/contacts_changed_event.dart";
import "package:photos/events/face_data_updated_event.dart";
import "package:photos/events/people_changed_event.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/photos_contacts_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/utils/avatar_util.dart";
import "package:photos/utils/contact_string_util.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";

final _logger = Logger("PersonFaceWidget");

class PersonFaceWidget extends StatefulWidget {
  static String coverHeroTag({
    required String tagPrefix,
    String? personId,
    String? clusterID,
  }) => personId != null
      ? "$tagPrefix:person_cover:$personId"
      : "$tagPrefix:cluster_cover:$clusterID";

  final String? personId;
  final String? clusterID;
  final bool useFullFile;
  final VoidCallback? onErrorCallback;
  final bool keepAlive;
  final Object? retryKey;

  // Physical pixels; null or non-positive decodes at full resolution.
  final int? cachedPixelWidth;

  const PersonFaceWidget({
    this.personId,
    this.clusterID,
    this.useFullFile = true,
    this.onErrorCallback,
    this.keepAlive = false,
    this.cachedPixelWidth,
    this.retryKey,
    super.key,
  }) : assert(
         personId != null || clusterID != null,
         "PersonFaceWidget requires either personId or clusterID to be non-null",
       );

  @override
  State<PersonFaceWidget> createState() => _PersonFaceWidgetState();
}

class _PersonFaceWidgetState extends State<PersonFaceWidget>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  Future<Uint8List?>? faceCropFuture;
  int? _faceCropFileId;
  int? _preferredFaceFileID;
  AvatarIdentity? _personIdentity;
  bool _showingFallback = false;
  bool _faceCropFailed = false;
  bool _fallbackEverUsed = false;
  bool _personHasContactLink = false;
  int? _linkedContactUserId;
  int _loadGeneration = 0;
  int _faceCropRetryRevision = 0;
  bool _usingAlternativeFace = false;
  bool _reloadingFaceData = false;
  final _faceCropCandidateFileIDs = <int>{};
  final _faceHydrationAttemptedFileIDs = <int>{};
  final _unavailableFaceDataFileIDs = <int>{};
  final _attemptedFaceCropIDs = <String>{};
  StreamSubscription<ContactsChangedEvent>? _contactsChangedSubscription;
  StreamSubscription<PeopleChangedEvent>? _peopleChangedSubscription;
  StreamSubscription<FaceDataUpdatedEvent>? _faceDataUpdatedSubscription;

  bool get isPerson => widget.personId != null;

  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _contactsChangedSubscription = Bus.instance
        .on<ContactsChangedEvent>()
        .listen(_onContactsChanged);
    _peopleChangedSubscription = Bus.instance.on<PeopleChangedEvent>().listen((
      event,
    ) {
      if (mounted && isPerson && event.person?.remoteID == widget.personId) {
        setState(() {
          faceCropFuture = _startFaceCropLoad();
        });
      }
    });
    _faceDataUpdatedSubscription = Bus.instance
        .on<FaceDataUpdatedEvent>()
        .listen(_onFaceDataUpdated);
    faceCropFuture = _startFaceCropLoad();
  }

  @override
  void didUpdateWidget(covariant PersonFaceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personId != widget.personId ||
        oldWidget.clusterID != widget.clusterID ||
        oldWidget.useFullFile != widget.useFullFile) {
      _personHasContactLink = false;
      _linkedContactUserId = null;
      _personIdentity = null;
      faceCropFuture = _startFaceCropLoad();
    } else if (widget.retryKey != null &&
        oldWidget.retryKey != widget.retryKey) {
      _faceCropRetryRevision++;
      if (_faceCropFailed) faceCropFuture = _startFaceCropLoad();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _contactsChangedSubscription?.cancel();
    _peopleChangedSubscription?.cancel();
    _faceDataUpdatedSubscription?.cancel();
    if (_faceCropFileId != null) {
      checkStopTryingToGenerateFaceThumbnails(
        _faceCropFileId!,
        useFullFile: widget.useFullFile,
      );
      if (_fallbackEverUsed) {
        checkStopTryingToGenerateFaceThumbnails(
          _faceCropFileId!,
          useFullFile: false,
        );
      }
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _faceCropRetryRevision++;
    if (_faceCropFailed || _usingAlternativeFace) {
      unawaited(_reloadAfterFaceDataUpdate());
    }
  }

  void _onContactsChanged(ContactsChangedEvent event) {
    if (!isPerson || !mounted) {
      return;
    }
    if (!_personHasContactLink && _linkedContactUserId == null) {
      return;
    }
    if (event.contactUserIds == null ||
        _linkedContactUserId == null ||
        event.matchesContactUserId(_linkedContactUserId)) {
      setState(() {
        faceCropFuture = _startFaceCropLoad();
      });
    }
  }

  void _onFaceDataUpdated(FaceDataUpdatedEvent event) {
    if (!mounted ||
        event.localGallery != isLocalGalleryMode ||
        !event.fileIDs.any(_faceCropCandidateFileIDs.contains)) {
      return;
    }
    if (_usingAlternativeFace &&
        !_faceCropFailed &&
        !event.fileIDs.contains(_preferredFaceFileID)) {
      return;
    }
    _faceCropRetryRevision++;
    if ((_faceCropFailed || _usingAlternativeFace) && !_reloadingFaceData) {
      unawaited(_reloadAfterFaceDataUpdate());
    }
  }

  Future<void> _reloadAfterFaceDataUpdate() async {
    if (!mounted || _reloadingFaceData) return;
    _reloadingFaceData = true;
    final generation = _loadGeneration;
    try {
      await checkRemoveCachedFaceIDForPersonOrClusterId(
        widget.personId ?? widget.clusterID!,
      );
      if (_isCurrentLoad(generation)) {
        setState(() {
          faceCropFuture = _startFaceCropLoad(retryRemote: false);
        });
      }
    } catch (e, s) {
      _logger.warning(
        "Failed to refresh face thumbnail after face data update",
        e,
        s,
      );
    } finally {
      _reloadingFaceData = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return FutureBuilder<Uint8List?>(
      future: faceCropFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          // Decode by width only so portrait crops retain enough height for
          // BoxFit.cover without upscaling.
          final shouldOptimize =
              widget.cachedPixelWidth != null && widget.cachedPixelWidth! > 0;
          final ImageProvider imageProvider = shouldOptimize
              ? Image.memory(
                  snapshot.data!,
                  cacheWidth: widget.cachedPixelWidth,
                ).image
              : MemoryImage(snapshot.data!);
          return Stack(
            fit: StackFit.expand,
            children: [
              Image(image: imageProvider, fit: BoxFit.cover),
              if (kDebugMode && _showingFallback)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "(T)",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.connectionState == ConnectionState.active) {
          return EnteLoadingWidget(
            color: getEnteColorScheme(context).fillMuted,
          );
        }
        if (snapshot.hasError) {
          _logger.severe(
            "Error getting cover face for person",
            snapshot.error,
            snapshot.stackTrace,
          );
        } else {
          _logger.severe(
            "faceCropFuture is null, no cover face found for person or cluster.",
          );
        }
        return _EmptyPersonThumbnail(identity: _personIdentity);
      },
    );
  }

  Future<Uint8List?> _startFaceCropLoad({bool retryRemote = true}) async {
    final generation = ++_loadGeneration;
    if (retryRemote) _unavailableFaceDataFileIDs.clear();
    _faceCropCandidateFileIDs.clear();
    _faceHydrationAttemptedFileIDs.clear();
    while (true) {
      _usingAlternativeFace = false;
      _preferredFaceFileID = null;
      _attemptedFaceCropIDs.clear();
      _faceCropFailed = false;
      final retryRevision = _faceCropRetryRevision;
      try {
        final crop = await _loadFaceCrop(generation);
        if (_isCurrentLoad(generation)) _faceCropFailed = crop == null;
        if (!_hasNewFaceCropRetry(generation, retryRevision) ||
            (crop != null && !_usingAlternativeFace)) {
          return crop;
        }
      } catch (_) {
        if (_isCurrentLoad(generation)) _faceCropFailed = true;
        if (!_hasNewFaceCropRetry(generation, retryRevision)) rethrow;
      }
    }
  }

  bool _hasNewFaceCropRetry(int generation, int retryRevision) =>
      _isCurrentLoad(generation) && _faceCropRetryRevision != retryRevision;

  Future<Uint8List?> _loadFaceCrop(int generation) async {
    final String personOrClusterId = widget.personId ?? widget.clusterID!;
    if (!widget.useFullFile) {
      final Uint8List? thumbnailCrop = await _getFaceCrop(
        generation: generation,
        useFullFile: widget.useFullFile,
      );
      if (_isCurrentLoad(generation) && thumbnailCrop != null) {
        _fallbackEverUsed = true;
        _showingFallback = false;
      }
      if (thumbnailCrop != null || isLocalGalleryMode) return thumbnailCrop;
      return _getAlternativeFaceCrop(generation);
    }

    final Uint8List? fullCrop = await _getFaceCrop(
      generation: generation,
      useFullFile: widget.useFullFile,
    );
    if (fullCrop != null) {
      if (_isCurrentLoad(generation)) {
        _showingFallback = false;
      }
      return fullCrop;
    }

    _logger.warning(
      "Full face crop unavailable for $personOrClusterId, attempting thumbnail fallback.",
    );

    final Uint8List? fallbackCrop = await _getFaceCrop(
      generation: generation,
      useFullFile: false,
    );
    if (fallbackCrop != null) {
      if (_isCurrentLoad(generation)) {
        _showingFallback = true;
        _fallbackEverUsed = true;
      }
      return fallbackCrop;
    }

    _logger.warning(
      "Thumbnail fallback also unavailable for $personOrClusterId.",
    );
    return isLocalGalleryMode ? null : _getAlternativeFaceCrop(generation);
  }

  Future<Uint8List?> _getAlternativeFaceCrop(int generation) async {
    final retryRevision = _faceCropRetryRevision;
    final db = MLDataDB.instance;
    final assigned = isPerson
        ? await db.getFaceIDsForPerson(widget.personId!)
        : await db.getFaceIDsForCluster(widget.clusterID!);
    if (!_isCurrentLoad(generation) || isLocalGalleryMode) return null;
    _faceCropCandidateFileIDs.addAll(
      assigned.map((faceID) => getFileIdFromFaceId<int>(faceID)),
    );
    final candidates = isPerson
        ? await db.getFaceIDsForPersonOrderedByScore(
            widget.personId!,
            limit: -1,
          )
        : await db.getFaceIDsForClusterOrderedByScore(
            widget.clusterID!,
            limit: -1,
          );
    final hiddenFileIDs = await SearchService.instance.getHiddenFiles().then(
      (files) => files.map((file) => file.uploadedFileID).toSet(),
    );
    final uncached = <String>[];
    for (final faceID in candidates) {
      if (!_isCurrentLoad(generation) ||
          isLocalGalleryMode ||
          _hasNewFaceCropRetry(generation, retryRevision)) {
        return null;
      }
      if (_attemptedFaceCropIDs.contains(faceID) ||
          hiddenFileIDs.contains(getFileIdFromFaceId<int>(faceID))) {
        continue;
      }
      final crop = await _tryAlternativeFaceCrop(
        faceID,
        generation,
        allowGeneration: false,
      );
      if (crop != null) return crop;
      uncached.add(faceID);
    }
    for (final faceID in uncached) {
      if (!_isCurrentLoad(generation) ||
          isLocalGalleryMode ||
          _hasNewFaceCropRetry(generation, retryRevision)) {
        return null;
      }
      final crop = await _tryAlternativeFaceCrop(
        faceID,
        generation,
        allowGeneration: true,
      );
      if (crop != null) return crop;
    }
    return null;
  }

  Future<Uint8List?> _tryAlternativeFaceCrop(
    String faceID,
    int generation, {
    required bool allowGeneration,
  }) async {
    final token = Configuration.instance.getToken();
    final fileID = getFileIdFromFaceId<int>(faceID);
    final file = await FilesDB.instance.getAnyUploadedFile(fileID);
    if (file == null) return null;
    final faces = await MLDataDB.instance.getFacesForGivenFileID(fileID);
    FaceWithoutEmbedding? face;
    for (final candidate in faces ?? <FaceWithoutEmbedding>[]) {
      if (candidate.faceID == faceID) {
        face = candidate;
        break;
      }
    }
    if (face == null ||
        !_isCurrentLoad(generation) ||
        isLocalGalleryMode ||
        Configuration.instance.getToken() != token) {
      return null;
    }
    _faceCropFileId = fileID;
    if (allowGeneration) _attemptedFaceCropIDs.add(faceID);
    for (final useFullFile in widget.useFullFile ? [true, false] : [false]) {
      final crops = await getCachedFaceCrops(
        file,
        [face],
        useFullFile: useFullFile,
        allowGeneration: allowGeneration,
        useTempCache: false,
      );
      if (!_isCurrentLoad(generation) ||
          isLocalGalleryMode ||
          Configuration.instance.getToken() != token) {
        return null;
      }
      final crop = crops?[faceID];
      if (crop == null) continue;
      await putFaceIdCachedForPersonOrCluster(
        widget.personId ?? widget.clusterID!,
        faceID,
      );
      if (!_isCurrentLoad(generation)) {
        return null;
      }
      _usingAlternativeFace = true;
      _showingFallback = widget.useFullFile && !useFullFile;
      _fallbackEverUsed = _fallbackEverUsed || !useFullFile;
      return crop;
    }
    return null;
  }

  Future<Uint8List?> _getFaceCrop({
    required int generation,
    required bool useFullFile,
  }) async {
    try {
      final String personOrClusterId = widget.personId ?? widget.clusterID!;
      final accountToken = Configuration.instance.getToken();
      String? fixedFaceID;
      Iterable<String>? assignedFaceIDs;
      PersonEntity? personEntity;
      final mlDataDB = isLocalGalleryMode
          ? MLDataDB.localGalleryInstance
          : MLDataDB.instance;
      if (isPerson && !isLocalGalleryMode) {
        personEntity =
            PersonService.instance.getCachedPerson(widget.personId!) ??
            await PersonService.instance.getPerson(widget.personId!);
        if (personEntity == null) {
          _logger.severe(
            "Person with ID ${widget.personId} not found, cannot get cover face.",
          );
          return null;
        }
        if (!_isCurrentLoad(generation)) {
          return null;
        }
        _personHasContactLink = _hasContactLink(personEntity);
        final contactPhotoBytes = await _getLinkedContactPhotoBytes(
          personEntity,
          generation: generation,
        );
        if (!_isCurrentLoad(generation)) {
          return null;
        }
        final personData = personEntity.data;
        final contact = PhotosContactsService.instance.getCachedContact(
          contactUserId: personData.userID,
          email: personData.email,
        );
        _personIdentity = AvatarIdentity.account(
          label: trimToNull(contact?.name) ?? personData.name,
          email: trimToNull(contact?.email) ?? personData.email,
          userID: personData.userID,
          personID: personEntity.remoteID,
          currentUserID: Configuration.instance.getUserID(),
          currentUserEmail: Configuration.instance.getEmail(),
        );
        if (contactPhotoBytes != null) {
          return contactPhotoBytes;
        }
        fixedFaceID = personEntity.data.avatarFaceID;
      } else {
        _personHasContactLink = false;
        _linkedContactUserId = null;
        _personIdentity = null;
      }
      final cachedFaceID = await checkUsedFaceIDForPersonOrClusterId(
        personOrClusterId,
      );
      if (fixedFaceID == null || fixedFaceID == cachedFaceID) {
        final cachedCrop = checkInMemoryCachedCropForPersonOrClusterID(
          personOrClusterId,
        );
        if (cachedCrop != null) return cachedCrop;
      }
      fixedFaceID ??= cachedFaceID;
      if (!_isCurrentLoad(generation)) return null;
      if (fixedFaceID != null && !isLocalGalleryMode) {
        _preferredFaceFileID = getFileIdFromFaceId<int>(fixedFaceID);
        _faceCropCandidateFileIDs.add(_preferredFaceFileID!);
      }

      EnteFile? fileForFaceCrop;
      if (isLocalGalleryMode) {
        final allFiles = await SearchService.instance.getAllFilesForSearch();
        final localIdToFile = <String, EnteFile>{};
        for (final file in allFiles) {
          final localId = file.localID;
          if (localId != null && localId.isNotEmpty) {
            localIdToFile[localId] = file;
          }
        }
        if (fixedFaceID != null) {
          final localIntId = getFileIdFromFaceId<int>(fixedFaceID);
          final localId = await OfflineFilesDB.instance.getLocalIdForIntId(
            localIntId,
          );
          if (localId == null) {
            await checkRemoveCachedFaceIDForPersonOrClusterId(
              personOrClusterId,
            );
          } else {
            fileForFaceCrop = localIdToFile[localId];
            if (fileForFaceCrop == null) {
              await checkRemoveCachedFaceIDForPersonOrClusterId(
                personOrClusterId,
              );
            }
          }
        }
        if (fileForFaceCrop == null) {
          final List<String> allFaces = isPerson
              ? await mlDataDB.getFaceIDsForPersonOrderedByScore(
                  widget.personId!,
                )
              : await mlDataDB.getFaceIDsForClusterOrderedByScore(
                  widget.clusterID!,
                );
          final localIntIds = allFaces
              .map((faceID) => getFileIdFromFaceId<int>(faceID))
              .toSet();
          final localIdMap = await OfflineFilesDB.instance.getLocalIdsForIntIds(
            localIntIds,
          );
          for (final faceID in allFaces) {
            final localIntId = getFileIdFromFaceId<int>(faceID);
            final localId = localIdMap[localIntId];
            final candidate = localId != null ? localIdToFile[localId] : null;
            if (candidate != null) {
              fileForFaceCrop = candidate;
              fixedFaceID = faceID;
              break;
            }
          }
          if (fileForFaceCrop == null) {
            _logger.severe(
              "No suitable local file found for face crop for person: ${widget.personId} or cluster: ${widget.clusterID}",
            );
            return null;
          }
        }
      } else {
        final hiddenFileIDs = await SearchService.instance
            .getHiddenFiles()
            .then((onValue) => onValue.map((e) => e.uploadedFileID).toSet());
        if (fixedFaceID != null) {
          final fileID = getFileIdFromFaceId<int>(fixedFaceID);
          final fileInDB = await FilesDB.instance.getAnyUploadedFile(fileID);
          if (fileInDB == null) {
            _logger.severe(
              "File with ID $fileID not found in DB, cannot get cover face.",
            );
            await checkRemoveCachedFaceIDForPersonOrClusterId(
              personOrClusterId,
            );
          } else if (hiddenFileIDs.contains(fileInDB.uploadedFileID)) {
            _logger.info(
              "File with ID $fileID is hidden, skipping it for face crop.",
            );
            await checkRemoveCachedFaceIDForPersonOrClusterId(
              personOrClusterId,
            );
          } else {
            fileForFaceCrop = fileInDB;
          }
        }
        if (fileForFaceCrop == null) {
          final scoredFaces = isPerson
              ? await mlDataDB.getFaceIDsForPersonOrderedByScore(
                  widget.personId!,
                  limit: -1,
                )
              : await mlDataDB.getFaceIDsForClusterOrderedByScore(
                  widget.clusterID!,
                  limit: -1,
                );
          final assignedFaces = isPerson
              ? await mlDataDB.getFaceIDsForPerson(widget.personId!)
              : await mlDataDB.getFaceIDsForCluster(widget.clusterID!);
          if (!_isCurrentLoad(generation)) return null;
          assignedFaceIDs = assignedFaces;
          _faceCropCandidateFileIDs.addAll(
            assignedFaces.map((faceID) => getFileIdFromFaceId<int>(faceID)),
          );
          final allFaces = <String>{...scoredFaces, ...assignedFaces};
          for (final faceID in allFaces) {
            final fileID = getFileIdFromFaceId<int>(faceID);
            if (hiddenFileIDs.contains(fileID)) {
              continue;
            }
            fileForFaceCrop = await FilesDB.instance.getAnyUploadedFile(fileID);
            if (fileForFaceCrop != null) {
              _logger.info(
                "Using file ID $fileID for face crop for person: ${widget.personId} or cluster: ${widget.clusterID}",
              );
              fixedFaceID = faceID;
              break;
            }
          }
          if (fileForFaceCrop == null) {
            _logger.severe(
              "No suitable file found for face crop for person: ${widget.personId} or cluster: ${widget.clusterID}",
            );
            return null;
          }
        }
      }
      int? recentFileID;
      if (isLocalGalleryMode) {
        final localId = fileForFaceCrop.localID;
        if (localId == null || localId.isEmpty) {
          _logger.severe(
            "Missing local ID for face crop for person: ${widget.personId} or cluster: ${widget.clusterID}",
          );
          return null;
        }
        recentFileID = await OfflineFilesDB.instance.getOrCreateLocalIntId(
          localId,
        );
      } else {
        recentFileID = fileForFaceCrop.uploadedFileID;
      }
      if (recentFileID == null) {
        _logger.severe(
          "Missing file id for face crop for person: ${widget.personId} or cluster: ${widget.clusterID}",
        );
        return null;
      }
      if (!_isCurrentLoad(generation)) return null;
      _faceCropCandidateFileIDs.add(recentFileID);
      _preferredFaceFileID ??= recentFileID;
      _faceCropFileId = recentFileID;
      FaceWithoutEmbedding? face = await mlDataDB.getCoverFaceForPerson(
        recentFileID: recentFileID,
        avatarFaceId: fixedFaceID,
        personID: widget.personId,
        clusterID: widget.clusterID,
      );
      if (!_isCurrentLoad(generation)) return null;
      if (face == null && !isLocalGalleryMode) {
        assignedFaceIDs ??= isPerson
            ? await mlDataDB.getFaceIDsForPerson(widget.personId!)
            : await mlDataDB.getFaceIDsForCluster(widget.clusterID!);
        if (!_isCurrentLoad(generation)) return null;
        _faceCropCandidateFileIDs.addAll(
          assignedFaceIDs.map((faceID) => getFileIdFromFaceId<int>(faceID)),
        );
        if (!_unavailableFaceDataFileIDs.contains(recentFileID) &&
            _faceHydrationAttemptedFileIDs.add(recentFileID)) {
          try {
            face = await PersonService.instance.getCoverFace(
              fileID: recentFileID,
              avatarFaceID: fixedFaceID,
              personID: widget.personId,
              clusterID: widget.clusterID,
            );
            if (face == null && _isCurrentLoad(generation)) {
              _unavailableFaceDataFileIDs.add(recentFileID);
            }
          } catch (e, s) {
            _logger.warning(
              "Failed to restore cover face for $personOrClusterId in file $recentFileID",
              e,
              s,
            );
          }
        }
        if (!_isCurrentLoad(generation) ||
            Configuration.instance.getToken() != accountToken) {
          return null;
        }
      }
      if (!_isCurrentLoad(generation)) return null;
      if (face == null) {
        _logger.severe(
          "No cover face for person: ${widget.personId} or cluster ${widget.clusterID} and fileID $recentFileID",
        );
        await checkRemoveCachedFaceIDForPersonOrClusterId(personOrClusterId);
        return null;
      }
      _attemptedFaceCropIDs.add(face.faceID);
      final cropMap = await getCachedFaceCrops(
        fileForFaceCrop,
        [face],
        useFullFile: useFullFile,
        useTempCache: false,
      );
      if (_isCurrentLoad(generation)) {
        _faceCropFileId = recentFileID;
      }
      final result = cropMap?[face.faceID];
      if (result != null) {
        if (!_isCurrentLoad(generation) ||
            Configuration.instance.getToken() != accountToken) {
          return null;
        }
        await putFaceIdCachedForPersonOrCluster(personOrClusterId, face.faceID);
        if (!_isCurrentLoad(generation) ||
            Configuration.instance.getToken() != accountToken) {
          return null;
        }
        _usingAlternativeFace = recentFileID != _preferredFaceFileID;
      }
      if (result == null) {
        _logger.severe(
          "Null cover face crop for person: ${widget.personId} or cluster ${widget.clusterID} and fileID $recentFileID",
        );
      }
      return result;
    } catch (e, s) {
      _logger.severe(
        "Error getting cover face for person: ${widget.personId} or cluster ${widget.clusterID}",
        e,
        s,
      );
      widget.onErrorCallback?.call();
      return null;
    }
  }

  bool _isCurrentLoad(int generation) =>
      mounted && _loadGeneration == generation;

  bool _hasContactLink(PersonEntity personEntity) {
    final userId = personEntity.data.userID;
    final email = personEntity.data.email?.trim();
    return (userId != null && userId > 0) ||
        (email != null && email.isNotEmpty);
  }

  Future<Uint8List?> _getLinkedContactPhotoBytes(
    PersonEntity personEntity, {
    required int generation,
  }) async {
    if (!_personHasContactLink) {
      _linkedContactUserId = null;
      return null;
    }
    final contact = await PhotosContactsService.instance.getContact(
      contactUserId: personEntity.data.userID,
      email: personEntity.data.email,
    );
    if (!_isCurrentLoad(generation)) {
      return null;
    }
    _linkedContactUserId = contact?.contactUserId ?? personEntity.data.userID;
    if (contact == null) {
      return null;
    }
    return PhotosContactsService.instance.getProfilePictureBytesByUserId(
      contact.contactUserId,
    );
  }
}

class _EmptyPersonThumbnail extends StatelessWidget {
  final AvatarIdentity? identity;

  const _EmptyPersonThumbnail({this.identity});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final hasIdentity = identity != null;
    return Container(
      decoration: BoxDecoration(
        color: hasIdentity
            ? avatarBackgroundColor(context, identity!)
            : colorScheme.fillFaint,
        border: Border.all(color: colorScheme.strokeFaint, width: 1),
      ),
      child: Center(
        child: hasIdentity
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final shortestSide = constraints.biggest.shortestSide.isFinite
                      ? constraints.biggest.shortestSide
                      : 0;
                  final fontSize = shortestSide > 0
                      ? shortestSide * 0.42
                      : textTheme.h2.fontSize ?? 24;
                  return Text(
                    identity!.initials,
                    style: textTheme.h2Bold.copyWith(
                      color: Colors.white,
                      fontSize: fontSize,
                      height: 1,
                    ),
                  );
                },
              )
            : Icon(Icons.person_outline, color: colorScheme.strokeMuted),
      ),
    );
  }
}
