import "dart:async";
import "dart:convert";
import "dart:developer";

import "package:computer/computer.dart";
import "package:ente_contacts/contacts.dart" as contacts;
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/gateways/entity/models/type.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/local_entity_data.dart";
import 'package:photos/models/ml/face/face.dart';
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/entity_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/photos_contacts_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/utils/contact_photo_util.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";
import "package:shared_preferences/shared_preferences.dart";

typedef ManualPersonAssignmentResult = ({
  PersonEntity person,
  List<int> addedFileIds,
  List<int> alreadyAssignedFileIds,
});
typedef PersonAvatarUpdateResult = ({
  PersonEntity person,
  bool contactPictureUpdateFailed,
});

class PersonService {
  static const Object _attributeNotProvided = Object();
  final EntityService entityService;
  final MLDataDB faceMLDataDB;
  final SharedPreferences prefs;
  final PhotosContactsService _contactsService;
  final _emailToPartialPersonDataMapCache = <String, Map<String, String>>{};
  final _userIdToPartialPersonDataMapCache = <int, Map<String, String>>{};

  PersonService(
    this.entityService,
    this.faceMLDataDB,
    this.prefs, {
    PhotosContactsService? contactsService,
  }) : _contactsService = contactsService ?? PhotosContactsService.instance;

  // instance
  static PersonService? _instance;
  static const kPersonIDKey = "person_id";
  static const kNameKey = "name";
  static const double kDefaultAutoMergeThreshold = 0.24;
  static double autoMergeThreshold = kDefaultAutoMergeThreshold;

  Future<List<PersonEntity>>? _cachedPersonsFuture;
  Map<String, PersonEntity>? _cachedPersonsById;
  int _personCacheGeneration = 0;
  int _cachedRemoteSyncTime = 0;

  static PersonService get instance {
    if (_instance == null) {
      throw Exception("PersonService not initialized");
    }
    return _instance!;
  }

  static bool get isInitialized => _instance != null;

  late Logger logger = Logger("PersonService");

  static void init(
    EntityService entityService,
    MLDataDB faceMLDataDB,
    SharedPreferences prefs,
  ) {
    _instance = PersonService(entityService, faceMLDataDB, prefs);
    final settings = LocalSettings(prefs);
    final savedAutoMerge = settings.autoMergeThresholdOverride;
    if (savedAutoMerge != null) {
      autoMergeThreshold = savedAutoMerge.clamp(0.0, 1.0);
    }
  }

  Map<String, Map<String, String>> get emailToPartialPersonDataMapCache =>
      _emailToPartialPersonDataMapCache;

  Map<String, String>? getCachedPartialPersonData({
    required int? userID,
    required String email,
  }) {
    final userIdMatch = userID != null && userID > 0
        ? _userIdToPartialPersonDataMapCache[userID]
        : null;
    return userIdMatch ?? _emailToPartialPersonDataMapCache[email];
  }

  void clearCache() {
    _emailToPartialPersonDataMapCache.clear();
    _userIdToPartialPersonDataMapCache.clear();
    _invalidatePersonCache();
    _cachedRemoteSyncTime = 0;
  }

  void _invalidatePersonCache() {
    _cachedPersonsFuture = null;
    _cachedPersonsById = null;
    _personCacheGeneration++;
  }

  Future<void> refreshPersonCache({
    bool notifyListeners = false,
    String source = "",
  }) async {
    _invalidatePersonCache();
    await getPersons();
    if (notifyListeners) {
      Bus.instance.fire(
        PeopleChangedEvent(type: PeopleEventType.syncDone, source: source),
      );
    }
  }

  Future<List<PersonEntity>> getCertainPersons(List<String> ids) async {
    final entities = await entityService.getCertainEntities(
      EntityType.cgroup,
      ids,
    );
    return entities
        .map(
          (e) => PersonEntity(e.id, PersonData.fromJson(json.decode(e.data))),
        )
        .toList();
  }

  int lastRemoteSyncTime() {
    return entityService.lastSyncTime(EntityType.cgroup);
  }

  Future<List<PersonEntity>> getPersons() async {
    final remoteSyncTime = lastRemoteSyncTime();
    if (_cachedRemoteSyncTime != remoteSyncTime) {
      _cachedRemoteSyncTime = remoteSyncTime;
      _invalidatePersonCache();
    }
    if (_cachedPersonsFuture == null) {
      final generation = _personCacheGeneration;
      _cachedPersonsFuture = _fetchAndCachePersons(generation);
    }
    return _cachedPersonsFuture!;
  }

  Future<List<PersonEntity>> _fetchAndCachePersons(int generation) async {
    logger.finest("reading all persons from local db");
    final entities = await entityService.getEntities(EntityType.cgroup);
    final persons = await Computer.shared().compute(
      _decodePersonEntities,
      param: {"entity": entities},
      taskName: "decode_person_entities",
    );
    if (generation != _personCacheGeneration) {
      return persons;
    }
    _cachedPersonsById = {
      for (final person in persons) person.remoteID: person,
    };
    _emailToPartialPersonDataMapCache.clear();
    _userIdToPartialPersonDataMapCache.clear();
    for (PersonEntity person in persons) {
      final partialData = {
        kPersonIDKey: person.remoteID,
        kNameKey: person.data.name,
      };
      final email = person.data.email;
      if (email != null && email.isNotEmpty) {
        _emailToPartialPersonDataMapCache[email] = partialData;
      }
      final userID = person.data.userID;
      if (userID != null && userID > 0) {
        _userIdToPartialPersonDataMapCache[userID] = partialData;
      }
    }

    return persons;
  }

  static List<PersonEntity> _decodePersonEntities(Map<String, dynamic> param) {
    final entities = param["entity"] as List<LocalEntityData>;
    return entities
        .map(
          (e) => PersonEntity(e.id, PersonData.fromJson(json.decode(e.data))),
        )
        .toList();
  }

  Future<PersonEntity?> getPerson(String id) {
    return entityService.getEntity(EntityType.cgroup, id).then((e) {
      if (e == null) {
        return null;
      }
      return PersonEntity(e.id, PersonData.fromJson(json.decode(e.data)));
    });
  }

  PersonEntity? getCachedPerson(String id) {
    if (_cachedRemoteSyncTime != lastRemoteSyncTime()) {
      return null;
    }
    return _cachedPersonsById?[id];
  }

  Future<Map<String, PersonEntity>> getPersonsMap() async {
    final persons = await getPersons();
    return _cachedPersonsById ??
        {for (final person in persons) person.remoteID: person};
  }

  Future<void> reconcileClusters() async {
    final EnteWatch? w = kDebugMode ? EnteWatch("reconcileClusters") : null;
    w?.start();
    await fetchRemoteClusterFeedback(skipClusterUpdateIfNoChange: false);
    w?.log("Stored remote feedback");
    final dbPersonClusterInfo = await faceMLDataDB
        .getPersonToClusterIdToFaceIds();
    w?.log("Got DB person cluster info");
    final persons = await getPersonsMap();
    w?.log("Got persons");
    int orphanMappingsRemoved = 0;
    for (var personID in dbPersonClusterInfo.keys) {
      final person = persons[personID];
      if (person == null) {
        logger.severe("Person $personID not found");
        await _removeOrphanedLocalPerson(personID);
        orphanMappingsRemoved++;
        continue;
      }
      final Map<String, Set<String>> dbPersonCluster =
          dbPersonClusterInfo[personID]!;
      final personData = person.data;
      final bool shouldUpdateAssigned = _shouldUpdateRemotePerson(
        personData,
        dbPersonCluster,
      );

      bool shouldUpdateManualAssignments = false;
      List<int>? updatedManualAssignments;
      if (personData.manuallyAssigned.isNotEmpty) {
        final manualFileIDs = personData.manuallyAssigned;
        final manualFileIDSet = manualFileIDs.toSet();
        final coveredManualFileIDs = <int>{};

        outerLoop:
        for (final faceIDs in dbPersonCluster.values) {
          for (final faceID in faceIDs) {
            final fileID = tryGetFileIdFromFaceId(faceID);
            if (fileID == null || !manualFileIDSet.contains(fileID)) {
              continue;
            }
            coveredManualFileIDs.add(fileID);
            if (coveredManualFileIDs.length == manualFileIDSet.length) {
              break outerLoop;
            }
          }
        }

        shouldUpdateManualAssignments = coveredManualFileIDs.isNotEmpty;
        if (shouldUpdateManualAssignments) {
          updatedManualAssignments = manualFileIDs
              .where((fileID) => !coveredManualFileIDs.contains(fileID))
              .toList();
        }
      }

      if (!shouldUpdateAssigned && !shouldUpdateManualAssignments) {
        continue;
      }

      if (shouldUpdateAssigned) {
        personData.assigned = dbPersonCluster.entries
            .map((e) => ClusterInfo(id: e.key, faces: e.value))
            .toList();
      }

      if (shouldUpdateManualAssignments) {
        personData.manuallyAssigned = updatedManualAssignments ?? <int>[];
      }

      _addOrUpdateEntity(
        EntityType.cgroup,
        personData.toJson(),
        id: personID,
      ).ignore();
      personData.logStats();
    }
    if (orphanMappingsRemoved > 0) {
      logger.warning(
        "Removed $orphanMappingsRemoved orphaned local person mappings during reconcile",
      );
    }
    w?.log("Reconciled clusters for ${persons.length} persons");
  }

  bool _shouldUpdateRemotePerson(
    PersonData personData,
    Map<String, Set<String>> dbPersonCluster,
  ) {
    if (personData.assigned.length != dbPersonCluster.length) {
      log(
        "Person ${personData.name} has ${personData.assigned.length} clusters, but ${dbPersonCluster.length} clusters found in DB",
        name: "PersonService",
      );
      return true;
    } else {
      for (ClusterInfo info in personData.assigned) {
        final dbCluster = dbPersonCluster[info.id];
        if (dbCluster == null) {
          log(
            "Cluster ${info.id} not found in DB for person ${personData.name}",
            name: "PersonService",
          );
          return true;
        }
        if (info.faces.length != dbCluster.length) {
          log(
            "Cluster ${info.id} has ${info.faces.length} faces, but ${dbCluster.length} faces found in DB",
            name: "PersonService",
          );
          return true;
        }
        for (var faceId in info.faces) {
          if (!dbCluster.contains(faceId)) {
            log(
              "Face $faceId not found in cluster ${info.id} for person ${personData.name}",
              name: "PersonService",
            );
            return true;
          }
        }
      }
    }
    return false;
  }

  Future<PersonEntity> addPerson({
    required String name,
    required String clusterID,
    bool isHidden = false,
    bool isPinned = false,
    bool hideFromMemories = false,
    String? birthdate,
    String? email,
    int? userID,
  }) async {
    final faceIds = await faceMLDataDB.getFaceIDsForCluster(clusterID);
    final data = PersonData(
      name: name,
      assigned: <ClusterInfo>[
        ClusterInfo(id: clusterID, faces: faceIds.toSet()),
      ],
      isHidden: isHidden,
      isPinned: isPinned,
      hideFromMemories: hideFromMemories,
      birthDate: birthdate,
      email: email,
      userID: userID,
    );
    final result = await _addOrUpdateEntity(EntityType.cgroup, data.toJson());
    await faceMLDataDB.assignClusterToPerson(
      personID: result.id,
      clusterID: clusterID,
    );
    if (data.email != null) {
      await refreshPersonCache();
    }
    memoriesCacheService.queueUpdateCache();
    return PersonEntity(result.id, data);
  }

  Future<void> removeClusterToPerson({
    required String personID,
    required String clusterID,
  }) async {
    final person = (await getPerson(personID))!;
    final personData = person.data;
    final clusterInfo = personData.assigned.firstWhere(
      (element) => element.id == clusterID,
      orElse: () => ClusterInfo(id: "noSuchClusterInRemotePerson", faces: {}),
    );
    if (clusterInfo.id == "noSuchClusterInRemotePerson") {
      await faceMLDataDB.removeClusterToPerson(
        personID: personID,
        clusterID: clusterID,
      );
      return;
    }
    personData.rejectedFaceIDs.addAll(clusterInfo.faces);
    personData.assigned.removeWhere((element) => element.id == clusterID);
    await _addOrUpdateEntity(
      EntityType.cgroup,
      personData.toJson(),
      id: personID,
    );
    await faceMLDataDB.removeClusterToPerson(
      personID: personID,
      clusterID: clusterID,
    );
    personData.logStats();
  }

  Future<void> removeFacesFromPerson({
    required PersonEntity person,
    required Set<String> faceIDs,
  }) async {
    final personData = person.data;

    // Remove faces from clusters
    final List<String> emptiedClusters = [];
    for (final cluster in personData.assigned) {
      cluster.faces.removeWhere((faceID) => faceIDs.contains(faceID));
      if (cluster.faces.isEmpty) {
        emptiedClusters.add(cluster.id);
      }
    }

    // Safety check to make sure we haven't created an empty cluster now, if so delete it
    for (final emptyClusterID in emptiedClusters) {
      personData.assigned.removeWhere(
        (element) => element.id == emptyClusterID,
      );
      await faceMLDataDB.removeClusterToPerson(
        personID: person.remoteID,
        clusterID: emptyClusterID,
      );
    }

    // Add removed faces to rejected faces
    personData.rejectedFaceIDs.addAll(faceIDs);

    await _addOrUpdateEntity(
      EntityType.cgroup,
      personData.toJson(),
      id: person.remoteID,
    );
    personData.logStats();
  }

  Future<void> deletePerson(String personID, {bool onlyMapping = false}) async {
    final entity = await getPerson(personID);
    if (onlyMapping) {
      if (entity == null) {
        return;
      }
      final PersonEntity justName = PersonEntity(
        personID,
        PersonData(name: entity.data.name),
      );
      await _addOrUpdateEntity(
        EntityType.cgroup,
        justName.data.toJson(),
        id: personID,
      );
      await faceMLDataDB.removePerson(personID);
      justName.data.logStats();

      if (entity.data.email != null) {
        await refreshPersonCache();
      }
    } else {
      await entityService.deleteEntry(personID);
      await faceMLDataDB.removePerson(personID);

      if (entity != null) {
        if (entity.data.email != null) {
          await refreshPersonCache();
        }
      }
    }

    // fire PeopleChangeEvent
    Bus.instance.fire(PeopleChangedEvent());
  }

  // fetchRemoteClusterFeedback returns true if remote data has changed
  Future<bool> fetchRemoteClusterFeedback({
    bool skipClusterUpdateIfNoChange = true,
  }) async {
    if (isLocalGalleryMode) {
      logger.finest("Skip fetching remote clusters in local gallery mode");
      return false;
    }
    final int changedEntities = await entityService.syncEntity(
      EntityType.cgroup,
    );
    final bool changed = changedEntities > 0;
    if (changed == false && skipClusterUpdateIfNoChange) {
      return false;
    }

    final entities = await entityService.getEntities(EntityType.cgroup);
    final remotePersonIDs = entities.map((e) => e.id).toSet();
    final localPersonMappings = await faceMLDataDB.getPersonToClusterIDs();
    int removedOrphans = 0;
    for (final localPersonID in localPersonMappings.keys) {
      if (!remotePersonIDs.contains(localPersonID)) {
        removedOrphans++;
        await _removeOrphanedLocalPerson(localPersonID);
      }
    }
    if (removedOrphans > 0) {
      logger.info(
        "Removed $removedOrphans orphaned local person mappings during sync",
      );
    }
    // todo: (neerajg) perf change, this can be expensive to do on every sync
    // especially when we have a lot of people. We should only do this when the
    // last sync time is updated for cgroup entity type. To avoid partial update,
    // we need to maintain a lastSyncTime value whenever this data is processed
    // and stored in the db.
    entities.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final Map<String, String> faceIdToClusterID = {};
    final Map<String, String> clusterToPersonID = {};
    bool shouldCheckRejectedFaces = false;
    for (var e in entities) {
      final personData = PersonData.fromJson(json.decode(e.data));
      if (personData.rejectedFaceIDs.isNotEmpty) {
        shouldCheckRejectedFaces = true;
      }
      int faceCount = 0;

      // Locally store the assignment of faces to clusters and people
      for (var cluster in personData.assigned) {
        faceCount += cluster.faces.length;
        for (var faceId in cluster.faces) {
          if (faceIdToClusterID.containsKey(faceId)) {
            if (flagService.internalUser) {
              final otherPersonID =
                  clusterToPersonID[faceIdToClusterID[faceId]!];
              if (otherPersonID != e.id) {
                final otherPerson = await getPerson(otherPersonID!);
                logger.warning(
                  "Face $faceId is already assigned to person $otherPersonID (${otherPerson!.data.name}) and person ${e.id} (${personData.name})",
                );
              }
            }
          } else {
            faceIdToClusterID[faceId] = cluster.id;
          }
        }
        clusterToPersonID[cluster.id] = e.id;
      }
      if (kDebugMode) {
        logger.info(
          "Person ${e.id} ${personData.name} has ${personData.assigned.length} clusters with $faceCount faces",
        );
      }
    }
    logger.info("Storing feedback for ${faceIdToClusterID.length} faces");
    await faceMLDataDB.updateFaceIdToClusterId(faceIdToClusterID);
    await faceMLDataDB.bulkAssignClusterToPersonID(clusterToPersonID);

    if (shouldCheckRejectedFaces) {
      final dbPeopleClusterInfo = await faceMLDataDB
          .getPersonToClusterIdToFaceIds();
      for (var e in entities) {
        final personData = PersonData.fromJson(json.decode(e.data));
        if (personData.rejectedFaceIDs.isNotEmpty) {
          final personClustersToFaceIDs = dbPeopleClusterInfo[e.id];
          if (personClustersToFaceIDs == null) {
            logger.warning(
              "Person ${e.id} ${personData.name} has rejected faces but no clusters found in local DB",
            );
            continue;
          }
          final personFaceIDs = personClustersToFaceIDs.values
              .expand((e) => e)
              .toSet();
          final rejectedFaceIDsSet = personData.rejectedFaceIDs.toSet();
          final assignedAndRejectedFaceIDs = rejectedFaceIDsSet.intersection(
            personFaceIDs,
          );

          if (assignedAndRejectedFaceIDs.isNotEmpty) {
            // Check that we don't have any empty clusters now
            final dbPersonClusterInfo = dbPeopleClusterInfo[e.id]!;
            final faceToClusterToRemove = <String, String>{};
            for (final clusterIdToFaceIDs in dbPersonClusterInfo.entries) {
              final clusterID = clusterIdToFaceIDs.key;
              final faceIDs = clusterIdToFaceIDs.value;
              final foundRejectedFacesToCluster = <String, String>{};
              final removeFaceIDs = <String>{};
              for (final faceID in faceIDs) {
                if (assignedAndRejectedFaceIDs.contains(faceID)) {
                  removeFaceIDs.add(faceID);
                  foundRejectedFacesToCluster[faceID] = clusterID;
                }
              }
              if (faceIDs.length == removeFaceIDs.length) {
                logger.info(
                  "Cluster $clusterID for person ${e.id} ${personData.name} is empty due to rejected faces from remote, removing the cluster from person",
                );
                await faceMLDataDB.removeClusterToPerson(
                  personID: e.id,
                  clusterID: clusterID,
                );
                await faceMLDataDB.captureNotPersonFeedback(
                  personID: e.id,
                  clusterID: clusterID,
                );
              } else {
                faceToClusterToRemove.addAll(foundRejectedFacesToCluster);
              }
            }
            // Remove the clusterID for the remaining conflicting faces
            await faceMLDataDB.removeFaceIdToClusterId(faceToClusterToRemove);
          }
        }
      }
    }

    return changed;
  }

  Future<PersonAvatarUpdateResult> updateAvatar(
    PersonEntity p,
    EnteFile file,
  ) async {
    final Face? face = await faceMLDataDB.getCoverFaceForPerson(
      recentFileID: file.uploadedFileID!,
      personID: p.remoteID,
    );
    if (face == null) {
      throw Exception(
        "No face found for person ${p.remoteID} in file ${file.uploadedFileID}",
      );
    }

    final person = (await getPerson(p.remoteID))!;
    var contactPictureUpdateFailed = false;
    try {
      await _updateLinkedContactAvatarBeforePerson(person, file, face);
    } catch (e, s) {
      contactPictureUpdateFailed = true;
      logger.warning("Failed to update linked contact picture", e, s);
    }
    final updatedPerson = person.copyWith(
      data: person.data.copyWith(avatarFaceId: face.faceID),
    );
    await updatePerson(updatedPerson);
    await putFaceIdCachedForPersonOrCluster(p.remoteID, face.faceID);
    return (
      person: updatedPerson,
      contactPictureUpdateFailed: contactPictureUpdateFailed,
    );
  }

  Future<void> _updateLinkedContactAvatarBeforePerson(
    PersonEntity person,
    EnteFile file,
    Face face,
  ) async {
    final contact = await _getLinkedContact(person);
    if (contact == null) {
      return;
    }
    final Uint8List? bytes = await buildContactPhotoAttachmentBytesFromFace(
      file: file,
      face: face,
    );
    if (bytes == null) {
      throw StateError(
        "Failed to prepare contact avatar for linked person ${person.remoteID}",
      );
    }
    await _contactsService.setProfilePicture(
      contactId: contact.id,
      bytes: bytes,
    );
  }

  Future<PersonEntity> updateAttributes(
    String id, {
    String? name,
    String? avatarFaceId,
    bool? isHidden,
    bool? isPinned,
    bool? hideFromMemories,
    Object? birthDate = _attributeNotProvided,
    Object? email = _attributeNotProvided,
    Object? userID = _attributeNotProvided,
    bool syncLinkedContactName = true,
  }) async {
    final person = (await getPerson(id))!;
    final trimmedName = name?.trim();
    var updatedData = person.data.copyWith(
      name: name,
      avatarFaceId: avatarFaceId,
      isHidden: isHidden,
      isPinned: isPinned,
      hideFromMemories: hideFromMemories,
    );
    if (!identical(birthDate, _attributeNotProvided)) {
      updatedData = updatedData.copyWith(birthDate: birthDate as String?);
    }
    if (!identical(email, _attributeNotProvided)) {
      updatedData = updatedData.copyWith(email: email as String?);
    }
    if (!identical(userID, _attributeNotProvided)) {
      updatedData = updatedData.copyWith(userID: userID as int?);
    }
    final updatedPerson = person.copyWith(data: updatedData);
    if (syncLinkedContactName &&
        trimmedName != null &&
        trimmedName.isNotEmpty &&
        trimmedName != person.data.name.trim()) {
      await _updateLinkedContactNameBeforePerson(updatedPerson, trimmedName);
    }
    await updatePerson(updatedPerson);
    await refreshPersonCache();
    if (hideFromMemories != null &&
        hideFromMemories != person.data.hideFromMemories) {
      memoriesCacheService.queueUpdateCache();
      if (hideFromMemories) {
        unawaited(memoriesCacheService.purgePersonFromMemoriesCache(id));
      }
    }
    return updatedPerson;
  }

  Future<void> _updateLinkedContactNameBeforePerson(
    PersonEntity person,
    String name,
  ) async {
    final contact = await _getLinkedContact(person);
    if (contact == null) {
      return;
    }
    await _contactsService.createOrUpdateContact(
      contactUserId: contact.contactUserId,
      name: name,
    );
  }

  Future<contacts.ContactRecord?> _getLinkedContact(PersonEntity person) =>
      _contactsService.getContact(
        contactUserId: person.data.userID,
        email: person.data.email,
      );

  Future<ManualPersonAssignmentResult> addManualFileAssignments({
    required String personID,
    required Set<int> fileIDs,
  }) async {
    final person = await getPerson(personID);
    if (person == null) {
      throw Exception("Person $personID not found");
    }
    if (fileIDs.isEmpty) {
      return (
        person: person,
        addedFileIds: const <int>[],
        alreadyAssignedFileIds: const <int>[],
      );
    }
    final existingClusterFileIds = await faceMLDataDB.getFileIdToClusterIDSet(
      personID,
    );
    final manualFileIDs = person.data.manuallyAssigned.toSet();
    final addedFileIDs = <int>[];
    final alreadyAssigned = <int>[];
    for (final id in fileIDs) {
      if (existingClusterFileIds.containsKey(id) ||
          manualFileIDs.contains(id)) {
        alreadyAssigned.add(id);
        continue;
      }
      addedFileIDs.add(id);
    }
    if (addedFileIDs.isEmpty) {
      return (
        person: person,
        addedFileIds: const <int>[],
        alreadyAssignedFileIds: alreadyAssigned,
      );
    }
    final updatedPerson = person.copyWith(
      data: person.data.copyWith(
        manuallyAssigned: [...manualFileIDs, ...addedFileIDs],
      ),
    );
    await updatePerson(updatedPerson);
    await refreshPersonCache();
    return (
      person: updatedPerson,
      addedFileIds: addedFileIDs,
      alreadyAssignedFileIds: alreadyAssigned,
    );
  }

  Future<void> updatePerson(PersonEntity updatePerson) async {
    try {
      await _addOrUpdateEntity(
        EntityType.cgroup,
        updatePerson.data.toJson(),
        id: updatePerson.remoteID,
      );
      updatePerson.data.logStats();
    } catch (e, s) {
      logger.severe("Failed to update person", e, s);
      rethrow;
    }
  }

  /// Wrapper method for entityService.addOrUpdate that handles cache refresh
  Future<LocalEntityData> _addOrUpdateEntity(
    EntityType type,
    Map<String, dynamic> jsonMap, {
    String? id,
  }) async {
    final result = await entityService.addOrUpdate(type, jsonMap, id: id);
    _invalidatePersonCache();
    return result;
  }

  Future<void> _removeOrphanedLocalPerson(String personID) async {
    logger.warning(
      "Removing local ML mappings for person $personID because entity no longer exists",
    );
    await faceMLDataDB.removePerson(personID);
  }
}
