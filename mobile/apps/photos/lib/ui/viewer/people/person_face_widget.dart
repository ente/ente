import "dart:async";
import "dart:typed_data";

import "package:flutter/foundation.dart" show kDebugMode;
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/offline_files_db.dart";
import "package:photos/events/contacts_changed_event.dart";
import "package:photos/events/people_changed_event.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/photos_contacts_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/utils/avatar_util.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";

final _logger = Logger("PersonFaceWidget");

class PersonFaceWidget extends StatefulWidget {
  final String? personId;
  final String? clusterID;
  final bool useFullFile;
  final VoidCallback? onErrorCallback;
  final bool keepAlive;

  /// Physical pixel width for image decoding optimization.
  ///
  /// When provided and > 0, the image will be decoded at this width, with height
  /// computed to preserve aspect ratio. This reduces memory usage for small displays.
  ///
  /// Typically calculated as: `(logicalWidth * MediaQuery.devicePixelRatioOf(context)).toInt()`
  ///
  /// If null or <= 0, the image is decoded at full resolution.
  final int? cachedPixelWidth;

  // PersonFaceWidget constructor checks that both personId and clusterID are not null
  // and that the file is not null
  const PersonFaceWidget({
    this.personId,
    this.clusterID,
    this.useFullFile = true,
    this.onErrorCallback,
    this.keepAlive = false,
    this.cachedPixelWidth,
    super.key,
  }) : assert(
         personId != null || clusterID != null,
         "PersonFaceWidget requires either personId or clusterID to be non-null",
       );

  @override
  State<PersonFaceWidget> createState() => _PersonFaceWidgetState();
}

class _PersonFaceWidgetState extends State<PersonFaceWidget>
    with AutomaticKeepAliveClientMixin {
  Future<Uint8List?>? faceCropFuture;
  int? _faceCropFileId;
  AvatarIdentity? _personIdentity;
  bool _showingFallback = false;
  bool _fallbackEverUsed = false;
  bool _personHasContactLink = false;
  int? _linkedContactUserId;
  int _loadGeneration = 0;
  StreamSubscription<ContactsChangedEvent>? _contactsChangedSubscription;
  StreamSubscription<PeopleChangedEvent>? _peopleChangedSubscription;

  bool get isPerson => widget.personId != null;

  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void initState() {
    super.initState();
    _contactsChangedSubscription = Bus.instance
        .on<ContactsChangedEvent>()
        .listen(_onContactsChanged);
    _peopleChangedSubscription = Bus.instance.on<PeopleChangedEvent>().listen((
      event,
    ) {
      if (mounted && isPerson && event.person?.remoteID == widget.personId) {
        setState(() => faceCropFuture = _startFaceCropLoad());
      }
    });
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
    }
  }

  @override
  void dispose() {
    _contactsChangedSubscription?.cancel();
    _peopleChangedSubscription?.cancel();
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

  @override
  Widget build(BuildContext context) {
    super.build(
      context,
    ); // Calling super.build for AutomaticKeepAliveClientMixin

    return FutureBuilder<Uint8List?>(
      future: faceCropFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          // Only cacheWidth (not cacheHeight) to preserve aspect ratio.
          // Face crops are typically portrait, so constraining width ensures
          // sufficient height for BoxFit.cover without upscaling.
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

  Future<Uint8List?> _startFaceCropLoad() {
    final generation = ++_loadGeneration;
    return _loadFaceCrop(generation);
  }

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
      return thumbnailCrop;
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
    return null;
  }

  Future<Uint8List?> _getFaceCrop({
    required int generation,
    required bool useFullFile,
  }) async {
    try {
      final String personOrClusterId = widget.personId ?? widget.clusterID!;
      String? fixedFaceID;
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
        final resolvedEmail = PhotosContactsService.instance
            .getCachedResolvedEmail(
              contactUserId: personData.userID,
              email: personData.userID == null ? personData.email : null,
            );
        final resolvedName = PhotosContactsService.instance.getCachedSavedName(
          contactUserId: personData.userID,
          email: personData.userID == null ? personData.email : null,
        );
        _personIdentity = AvatarIdentity.account(
          label: resolvedName ?? personData.name,
          email: resolvedEmail ?? personData.email,
          userID: personData.userID,
          personID: personEntity.remoteID,
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
      final tryInMemoryCachedCrop = checkInMemoryCachedCropForPersonOrClusterID(
        personOrClusterId,
      );
      if (tryInMemoryCachedCrop != null) return tryInMemoryCachedCrop;
      fixedFaceID ??= await checkUsedFaceIDForPersonOrClusterId(
        personOrClusterId,
      );

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
            .then((onValue) => onValue.map((e) => e.uploadedFileID));
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
          final List<String> allFaces = isPerson
              ? await mlDataDB.getFaceIDsForPersonOrderedByScore(
                  widget.personId!,
                )
              : await mlDataDB.getFaceIDsForClusterOrderedByScore(
                  widget.clusterID!,
                );
          for (final faceID in allFaces) {
            final fileID = getFileIdFromFaceId<int>(faceID);
            if (hiddenFileIDs.contains(fileID)) {
              _logger.info(
                "File with ID $fileID is hidden, skipping it for face crop.",
              );
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
      final Face? face = await mlDataDB.getCoverFaceForPerson(
        recentFileID: recentFileID,
        avatarFaceId: fixedFaceID,
        personID: widget.personId,
        clusterID: widget.clusterID,
      );
      if (face == null) {
        _logger.severe(
          "No cover face for person: ${widget.personId} or cluster ${widget.clusterID} and fileID $recentFileID",
        );
        await checkRemoveCachedFaceIDForPersonOrClusterId(personOrClusterId);
        return null;
      }
      final cropMap = await getCachedFaceCrops(
        fileForFaceCrop,
        [face],
        useFullFile: useFullFile,
        personOrClusterID: personOrClusterId,
        useTempCache: false,
      );
      if (_isCurrentLoad(generation)) {
        _faceCropFileId = recentFileID;
      }
      final result = cropMap?[face.faceID];
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

  bool _isCurrentLoad(int generation) => _loadGeneration == generation;

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
                    identity!.initial,
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
