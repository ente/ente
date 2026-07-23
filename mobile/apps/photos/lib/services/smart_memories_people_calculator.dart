part of "smart_memories_service.dart";

class PeopleMemoriesCalculator {
  static Future<List<PeopleMemory>> compute(
    Map<int, EnteFile> allFileIdsToFile,
    DateTime currentTime,
    List<PeopleShownLog> shownPeople, {
    bool surfaceAll = false,
    required Map<int, int> seenTimes,
    required List<PersonEntity> persons,
    required bool isLocalGalleryMode,
    required bool canUseUnnamedFallback,
    String? currentUserEmail,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Map<String, int> clusterIdToFaceCount,
    required Map<String, Iterable<String>> clusterIdToFaceIDs,
    required Set<String> assignedClusterIDs,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
    required Map<PeopleActivity, Vector> clipPeopleActivityVectors,
  }) async {
    final w = (kDebugMode ? EnteWatch('getPeopleResults') : null)?..start();
    final List<PeopleMemory> memoryResults = [];
    if (allFileIdsToFile.isEmpty) return [];
    final nowInMicroseconds = currentTime.microsecondsSinceEpoch;
    final windowEnd = currentTime
        .add(kMemoriesUpdateFrequency)
        .microsecondsSinceEpoch;
    w?.log('allFiles setup');

    final personIdToPerson = <String, PersonEntity>{};
    final personIdToFaceIDs = <String, Set<String>>{};
    final personIdToFileIDs = <String, Set<int>>{};
    for (final person in persons) {
      final personID = person.remoteID;
      personIdToPerson[personID] = person;
      personIdToFaceIDs[personID] = {};
      personIdToFileIDs[personID] = {};
      for (final cluster in person.data.assigned) {
        if (cluster.faces.isEmpty) continue;
        personIdToFaceIDs[personID]!.addAll(cluster.faces);
        personIdToFileIDs[personID]!.addAll(
          cluster.faces.map((faceID) => getFileIdFromFaceId(faceID)),
        );
      }
    }
    final List<String> orderedImportantPersonsID = persons
        .where((person) => !isLocalGalleryMode && !person.data.isIgnored)
        .map((p) => p.remoteID)
        .toList();
    orderedImportantPersonsID.shuffle(Random());
    final amountOfPersons = orderedImportantPersonsID.length;
    final shownPersonTimeout = Duration(
      days: min(
        kPersonShowTimeout.inDays,
        max(1, amountOfPersons) * kMemoriesUpdateFrequencyDays,
      ),
    );
    w?.log('orderedImportantPersonsID setup');

    String? meID;
    for (final personEntity in persons) {
      if (personEntity.data.email == currentUserEmail) {
        meID = personEntity.remoteID;
        break;
      }
    }
    final bool isMeAssigned = meID != null;
    Set<int>? meFileIDs;
    if (isMeAssigned) meFileIDs = personIdToFileIDs[meID]!;

    Future<List<Memory>> selectPeopleMemories(List<Memory> memories) {
      return SmartMemoriesService._bestSelectionPeople(
        memories,
        isLocalGalleryMode: isLocalGalleryMode,
        fileIDToImageEmbedding: fileIDToImageEmbedding,
        clipPositiveTextVector: clipPositiveTextVector,
      );
    }

    final unnamedClusterCandidates =
        SmartMemoriesService._buildUnnamedClusterCandidates(
          clusterIdToFaceCount: clusterIdToFaceCount,
          clusterIdToFaceIDs: clusterIdToFaceIDs,
          assignedClusterIDs: assignedClusterIDs,
          allFileIdsToFile: allFileIdsToFile,
          fileIdToFaces: fileIdToFaces,
          meFileIDs: meFileIDs,
          isMeAssigned: isMeAssigned,
          seenTimes: seenTimes,
          nowInMicroseconds: nowInMicroseconds,
          windowEnd: windowEnd,
          isLocalGalleryMode: isLocalGalleryMode,
          selectionBuilder: selectPeopleMemories,
        );
    final randomizedUnnamedClusterCandidates =
        SmartMemoriesService._orderUnnamedCandidatesByRecencyAndRandom(
          candidates: unnamedClusterCandidates,
          shownPeople: shownPeople,
          currentTime: currentTime,
          shownPersonTimeout: shownPersonTimeout,
        );
    w?.log('unnamed cluster candidates setup');

    if (kDebugMode && SmartMemoriesService._debugForceUnnamedClustersOnly) {
      for (final candidate in randomizedUnnamedClusterCandidates) {
        final memory = await candidate.realize();
        if (memory == null) continue;
        memoryResults.add(memory);
        if (!surfaceAll) break;
      }
      return memoryResults;
    }

    final Map<String, Map<PeopleMemoryType, List<PeopleMemoryCandidate>>>
    personToCandidates = {};
    for (final personID in orderedImportantPersonsID) {
      final personFileIDs = personIdToFileIDs[personID]!;
      final personName = personIdToPerson[personID]!.data.name;
      w?.log('start with new person $personName');
      w?.log('personFilesToFaces setup');

      final spotlightFiles = <EnteFile>[];
      for (final fileID in personFileIDs) {
        final int personsPresent = fileIdToFaces[fileID]?.length ?? 10;
        if (personsPresent > 1) continue;
        final file = allFileIdsToFile[fileID];
        if (file != null) {
          spotlightFiles.add(file);
        }
      }
      if (spotlightFiles.length > SmartMemoriesService.minimumMemoryLength) {
        final spotlightMemories = spotlightFiles
            .map((f) => Memory.fromFile(f, seenTimes))
            .toList(growable: false);
        final spotlightList = personToCandidates
            .putIfAbsent(personID, () => {})
            .putIfAbsent(
              PeopleMemoryType.spotlight,
              () => <PeopleMemoryCandidate>[],
            );
        spotlightList.add(
          PeopleMemoryCandidate(
            personID: personID,
            personName: (isMeAssigned && meID == personID) ? null : personName,
            type: PeopleMemoryType.spotlight,
            rawMemories: spotlightMemories,
            firstDateToShow: nowInMicroseconds,
            lastDateToShow: windowEnd,
            selectionBuilder: selectPeopleMemories,
          ),
        );
      }
      w?.log('spotlight setup');

      if (isMeAssigned && meID != personID) {
        final youAndThemFiles = <EnteFile>[];
        for (final fileID in personFileIDs) {
          final bool mePresent = meFileIDs!.contains(fileID);
          final personFaces = fileIdToFaces[fileID] ?? [];
          if (!mePresent || personFaces.length != 2) continue;
          final file = allFileIdsToFile[fileID];
          if (file != null) {
            youAndThemFiles.add(file);
          }
        }
        if (youAndThemFiles.length > SmartMemoriesService.minimumMemoryLength) {
          final youAndThemMemories = youAndThemFiles
              .map((f) => Memory.fromFile(f, seenTimes))
              .toList(growable: false);
          final youAndThemList = personToCandidates
              .putIfAbsent(personID, () => {})
              .putIfAbsent(
                PeopleMemoryType.youAndThem,
                () => <PeopleMemoryCandidate>[],
              );
          youAndThemList.add(
            PeopleMemoryCandidate(
              personID: personID,
              personName: personName,
              type: PeopleMemoryType.youAndThem,
              rawMemories: youAndThemMemories,
              firstDateToShow: nowInMicroseconds,
              lastDateToShow: windowEnd,
              selectionBuilder: selectPeopleMemories,
            ),
          );
        }
        w?.log('youAndThem setup');
      }

      if (isMeAssigned && meID != personID) {
        final vectors = SmartMemoriesService._getEmbeddingsForFileIDs(
          fileIDToImageEmbedding,
          personFileIDs,
        );
        w?.log('getting clip vectors for doingSomethingTogether');
        final activityFiles = <EnteFile>[];
        for (final activity in PeopleActivity.values) {
          activityFiles.clear();
          final Vector? activityVector = clipPeopleActivityVectors[activity];
          if (activityVector == null) {
            dev.log("No vector for activity $activity");
            continue;
          }
          final Map<int, double> similarities = {};
          for (final embedding in vectors) {
            similarities[embedding.fileID] = embedding.vector.dot(
              activityVector,
            );
          }
          w?.log(
            'comparing embeddings for doingSomethingTogether and $activity',
          );
          for (final fileID in personFileIDs) {
            final similarity = similarities[fileID];
            if (similarity == null) continue;
            if (similarity > SmartMemoriesService._clipActivityQueryThreshold) {
              final file = allFileIdsToFile[fileID];
              if (file != null) {
                activityFiles.add(file);
              }
            }
          }
          if (activityFiles.length > SmartMemoriesService.minimumMemoryLength) {
            final activityMemories = activityFiles
                .map((f) => Memory.fromFile(f, seenTimes))
                .toList(growable: false);
            final activityList = personToCandidates
                .putIfAbsent(personID, () => {})
                .putIfAbsent(
                  PeopleMemoryType.doingSomethingTogether,
                  () => <PeopleMemoryCandidate>[],
                );
            activityList.add(
              PeopleMemoryCandidate(
                personID: personID,
                personName: personName,
                type: PeopleMemoryType.doingSomethingTogether,
                rawMemories: activityMemories,
                firstDateToShow: nowInMicroseconds,
                lastDateToShow: windowEnd,
                activity: activity,
                selectionBuilder: selectPeopleMemories,
              ),
            );
          }
        }

        w?.log('doingSomethingTogether setup');
      }

      final lastTimeYouSawThemFiles = <EnteFile>[];
      int lastCreationTime = 0;
      bool longAgo = true;
      for (final fileID in personFileIDs) {
        final file = allFileIdsToFile[fileID];
        if (file != null && file.creationTime != null) {
          final creationTime = file.creationTime!;
          final creationDateTime = DateTime.fromMicrosecondsSinceEpoch(
            creationTime,
          );
          if (currentTime.difference(creationDateTime).inDays < 365) {
            longAgo = false;
            break;
          }
          if (creationTime > lastCreationTime - microSecondsInDay) {
            final lastDateTime = DateTime.fromMicrosecondsSinceEpoch(
              lastCreationTime,
            );
            if (creationDateTime.difference(lastDateTime).inHours > 24) {
              lastTimeYouSawThemFiles.clear();
            }
            if (creationTime > lastCreationTime) {
              lastCreationTime = creationTime;
            }
            lastTimeYouSawThemFiles.add(file);
          }
        }
      }
      if (longAgo && lastTimeYouSawThemFiles.length >= 2 && meID != personID) {
        final lastTimeMemories = lastTimeYouSawThemFiles
            .map((f) => Memory.fromFile(f, seenTimes))
            .toList();
        lastTimeMemories.sort(
          (a, b) => a.file.creationTime!.compareTo(b.file.creationTime!),
        );
        final filteredLastTimeMemories =
            SmartMemoriesService._filterNearDuplicates(
              lastTimeMemories,
              fileIDToImageEmbedding,
              minKeep: 2,
              isLocalGalleryMode: isLocalGalleryMode,
            );
        final spacedLastTimeMemories =
            SmartMemoriesService._filterByTimeSpacing(filteredLastTimeMemories);
        final lastTimeList = personToCandidates
            .putIfAbsent(personID, () => {})
            .putIfAbsent(
              PeopleMemoryType.lastTimeYouSawThem,
              () => <PeopleMemoryCandidate>[],
            );
        lastTimeList.add(
          PeopleMemoryCandidate(
            personID: personID,
            personName: personName,
            type: PeopleMemoryType.lastTimeYouSawThem,
            rawMemories: spacedLastTimeMemories,
            firstDateToShow: nowInMicroseconds,
            lastDateToShow: windowEnd,
            lastCreationTime: lastCreationTime,
            requiresSelection: false,
          ),
        );
      }
      w?.log('lastTimeYouSawThem setup');
    }

    if (surfaceAll) {
      for (final personCandidates in personToCandidates.values) {
        for (final candidateList in personCandidates.values) {
          for (final candidate in candidateList) {
            final memory = await candidate.realize();
            if (memory != null) {
              memoryResults.add(memory);
            }
          }
        }
      }
      for (final candidate in unnamedClusterCandidates) {
        final memory = await candidate.realize();
        if (memory != null) {
          memoryResults.add(memory);
        }
      }
      return memoryResults;
    }

    for (final personID in orderedImportantPersonsID) {
      final personCandidates = personToCandidates[personID];
      if (personCandidates == null) continue;
      final person = personIdToPerson[personID]!;

      final lastMetCandidate =
          personCandidates[PeopleMemoryType.lastTimeYouSawThem]?.first;
      if (lastMetCandidate != null &&
          lastMetCandidate.lastCreationTime != null) {
        final lastMetTime = DateTime.fromMicrosecondsSinceEpoch(
          lastMetCandidate.lastCreationTime!,
        ).copyWith(year: currentTime.year);
        final daysSinceLastMet = lastMetTime.difference(currentTime).inDays;
        if (daysSinceLastMet < 7 && daysSinceLastMet >= 0) {
          final lastMetMemory = await lastMetCandidate.realize();
          if (lastMetMemory != null) {
            memoryResults.add(lastMetMemory);
          }
        }
      }

      final birthdate = DateTime.tryParse(person.data.birthDate ?? "");
      if (birthdate != null) {
        final thisBirthday = DateTime(
          currentTime.year,
          birthdate.month,
          birthdate.day,
        );
        final daysTillBirthday = thisBirthday.difference(currentTime).inDays;
        if (daysTillBirthday < 6 && daysTillBirthday >= 0) {
          final int newAge = currentTime.year - birthdate.year;
          final spotlightCandidate =
              personCandidates[PeopleMemoryType.spotlight]?.first;
          if (spotlightCandidate != null &&
              spotlightCandidate.personName != null) {
            final spotlightMem = await spotlightCandidate.realize();
            if (spotlightMem != null) {
              final thisBirthday = birthdate.copyWith(year: currentTime.year);
              memoryResults.add(
                spotlightMem.copyWith(
                  isBirthday: false,
                  newAge: newAge,
                  firstDateToShow: thisBirthday
                      .subtract(const Duration(days: 5))
                      .microsecondsSinceEpoch,
                  lastDateToShow: thisBirthday.microsecondsSinceEpoch,
                ),
              );
              memoryResults.add(
                spotlightMem.copyWith(
                  isBirthday: true,
                  newAge: newAge,
                  firstDateToShow: thisBirthday.microsecondsSinceEpoch,
                  lastDateToShow: thisBirthday
                      .add(kDayItself)
                      .microsecondsSinceEpoch,
                ),
              );
            }
          }
          final youAndThemCandidate =
              personCandidates[PeopleMemoryType.youAndThem]?.first;
          if (youAndThemCandidate != null) {
            final youAndThemMem = await youAndThemCandidate.realize();
            if (youAndThemMem != null) {
              memoryResults.add(
                youAndThemMem.copyWith(
                  isBirthday: false,
                  newAge: newAge,
                  firstDateToShow: thisBirthday
                      .subtract(const Duration(days: 5))
                      .microsecondsSinceEpoch,
                  lastDateToShow: thisBirthday.microsecondsSinceEpoch,
                ),
              );
              memoryResults.add(
                youAndThemMem.copyWith(
                  isBirthday: true,
                  newAge: newAge,
                  firstDateToShow: thisBirthday.microsecondsSinceEpoch,
                  lastDateToShow: thisBirthday
                      .add(kDayItself)
                      .microsecondsSinceEpoch,
                ),
              );
            }
          }
        }
      }
    }
    w?.log('relevancy setup');

    final shownPersonAndTypeTimeout = Duration(
      days: shownPersonTimeout.inDays * 2,
    );
    bool addedFromRotation = false;
    peopleRotationLoop:
    for (final personID in orderedImportantPersonsID) {
      for (final memory in memoryResults) {
        if (memory.personID == personID) {
          continue peopleRotationLoop;
        }
      }
      for (final shownLog in shownPeople) {
        if (shownLog.personID != personID) continue;
        final shownDate = DateTime.fromMicrosecondsSinceEpoch(
          shownLog.lastTimeShown,
        );
        final bool seenPersonRecently =
            currentTime.difference(shownDate) < shownPersonTimeout;
        if (seenPersonRecently) continue peopleRotationLoop;
      }
      final personCandidates = personToCandidates[personID];
      if (personCandidates == null) continue peopleRotationLoop;
      int added = 0;
      final amountOfMemoryTypesForPerson = personCandidates.length;
      final bool manyMemoryTypes = amountOfMemoryTypesForPerson > 2;
      potentialMemoryLoop:
      for (final candidatesForCategory in personCandidates.values) {
        if (candidatesForCategory.isEmpty) continue;
        PeopleMemoryCandidate potentialCandidate = candidatesForCategory.first;
        if (candidatesForCategory.length > 1) {
          if (potentialCandidate.type !=
              PeopleMemoryType.doingSomethingTogether) {
            dev.log(
              'Something is going wrong, ${potentialCandidate.type} has multiple memories for same person',
            );
          } else {
            final randIdx = Random().nextInt(candidatesForCategory.length);
            potentialCandidate = candidatesForCategory[randIdx];
          }
        }
        for (final shownLog in shownPeople) {
          if (shownLog.personID != personID) continue;
          if (shownLog.peopleMemoryType != potentialCandidate.type) {
            continue;
          }
          final shownTypeDate = DateTime.fromMicrosecondsSinceEpoch(
            shownLog.lastTimeShown,
          );
          final bool seenPersonTypeRecently =
              currentTime.difference(shownTypeDate) < shownPersonAndTypeTimeout;
          if (manyMemoryTypes && seenPersonTypeRecently) {
            continue potentialMemoryLoop;
          }
        }
        final potentialMemory = await potentialCandidate.realize();
        if (potentialMemory == null) continue;
        memoryResults.add(potentialMemory);
        addedFromRotation = true;
        added++;
        if (added >= 2) break peopleRotationLoop;
      }
      if (added > 0) break peopleRotationLoop;
    }
    if (!addedFromRotation && canUseUnnamedFallback) {
      final eligibleUnnamedCandidates = <PeopleMemoryCandidate>[];
      for (final candidate in randomizedUnnamedClusterCandidates) {
        final candidatePersonID = candidate.personID;
        bool alreadyInResults = false;
        for (final memory in memoryResults) {
          if (memory.personID == candidatePersonID) {
            alreadyInResults = true;
            break;
          }
        }
        if (alreadyInResults) {
          continue;
        }
        if (SmartMemoriesService._wasPersonShownRecently(
          personID: candidatePersonID,
          shownPeople: shownPeople,
          currentTime: currentTime,
          shownPersonTimeout: shownPersonTimeout,
        )) {
          continue;
        }
        eligibleUnnamedCandidates.add(candidate);
      }
      final orderedEligibleUnnamedCandidates =
          SmartMemoriesService._orderUnnamedCandidatesByRecencyAndRandom(
            candidates: eligibleUnnamedCandidates,
            shownPeople: shownPeople,
            currentTime: currentTime,
            shownPersonTimeout: shownPersonTimeout,
          );
      for (final candidate in orderedEligibleUnnamedCandidates) {
        final potentialMemory = await candidate.realize();
        if (potentialMemory == null) {
          continue;
        }
        memoryResults.add(potentialMemory);
        break;
      }
    }
    w?.log('rotation setup');

    return memoryResults;
  }
}
