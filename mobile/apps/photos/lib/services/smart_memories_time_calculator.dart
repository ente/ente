part of "smart_memories_service.dart";

class TimeMemoriesCalculator {
  static const _recentTimeMemorySelectionSize = 10;

  static Future<List<TimeMemory>> computeTimeMemories(
    Iterable<EnteFile> allFiles,
    DateTime currentTime, {
    Iterable<EnteFile>? recentSourceFiles,
    required bool isLocalGalleryMode,
    required bool mlEnabled,
    required Map<int, int> seenTimes,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Map<String, String> faceIDsToPersonID,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
  }) async {
    final List<TimeMemory> recentMemoryResult = [];
    final List<TimeMemory> historicalMemoryResult = [];
    final availableFiles = allFiles is List<EnteFile>
        ? allFiles
        : allFiles.toList();
    if (availableFiles.isEmpty) return [];
    final recentCandidates = recentSourceFiles ?? availableFiles;

    final startOfCurrentWeek = _startOfWeek(currentTime);
    final startOfPreviousWeek = startOfCurrentWeek.subtract(
      const Duration(days: 7),
    );
    await _maybeAddRecentTimeMemory(
      recentMemoryResult,
      recentCandidates,
      sourceStart: startOfPreviousWeek,
      sourceEnd: startOfCurrentWeek,
      showStart: startOfCurrentWeek,
      showEnd: startOfCurrentWeek.add(const Duration(days: 7)),
      kind: TimeMemoryKind.lastWeek,
      isLocalGalleryMode: isLocalGalleryMode,
      mlEnabled: mlEnabled,
      seenTimes: seenTimes,
      fileIdToFaces: fileIdToFaces,
      faceIDsToPersonID: faceIDsToPersonID,
      fileIDToImageEmbedding: fileIDToImageEmbedding,
      clipPositiveTextVector: clipPositiveTextVector,
    );

    final startOfCurrentMonth = _startOfMonth(currentTime);
    final startOfPreviousMonth = DateTime(
      startOfCurrentMonth.year,
      startOfCurrentMonth.month - 1,
    );
    await _maybeAddRecentTimeMemory(
      recentMemoryResult,
      recentCandidates,
      sourceStart: startOfPreviousMonth,
      sourceEnd: startOfCurrentMonth,
      showStart: startOfCurrentMonth,
      showEnd: DateTime(
        startOfCurrentMonth.year,
        startOfCurrentMonth.month + 1,
      ),
      kind: TimeMemoryKind.lastMonth,
      isLocalGalleryMode: isLocalGalleryMode,
      mlEnabled: mlEnabled,
      seenTimes: seenTimes,
      fileIdToFaces: fileIdToFaces,
      faceIDsToPersonID: faceIDsToPersonID,
      fileIDToImageEmbedding: fileIDToImageEmbedding,
      clipPositiveTextVector: clipPositiveTextVector,
    );

    final currentDayMonth = currentTime.month * 100 + currentTime.day;
    final currentWeek = getWeekNumber(currentTime);
    final currentMonth = currentTime.month;
    final currentYear = currentTime.year;
    final cutOffTime = currentTime.subtract(const Duration(days: 365));
    final averageDailyPhotos = availableFiles.length / 365;
    final significantDayThreshold = averageDailyPhotos * 0.25;
    final significantWeekThreshold = averageDailyPhotos * 0.40;

    final dayMonthYearGroups = <int, Map<int, List<Memory>>>{};

    for (final file in availableFiles) {
      if (file.creationTime! > cutOffTime.microsecondsSinceEpoch) continue;

      final creationTime = DateTime.fromMicrosecondsSinceEpoch(
        file.creationTime!,
      );
      final dayMonth = creationTime.month * 100 + creationTime.day;
      final year = creationTime.year;

      dayMonthYearGroups
          .putIfAbsent(dayMonth, () => {})
          .putIfAbsent(year, () => [])
          .add(Memory.fromFile(file, seenTimes));
    }

    for (final dayMonth in dayMonthYearGroups.keys) {
      final dayDiff = dayMonth - currentDayMonth;
      if (dayDiff < 0 || dayDiff > kMemoriesUpdateFrequency.inDays) continue;

      final yearGroups = dayMonthYearGroups[dayMonth]!;
      final significantDays = yearGroups.entries
          .where((e) => e.value.length > significantDayThreshold)
          .map((e) => e.key)
          .toList();

      if (significantDays.length >= 3) {
        final date = DateTime(
          currentTime.year,
          dayMonth ~/ 100,
          dayMonth % 100,
        );
        final allPhotos = yearGroups.values.expand((x) => x).toList();
        final photoSelection = await SmartMemoriesService._bestSelection(
          allPhotos,
          isLocalGalleryMode: isLocalGalleryMode,
          mlEnabled: mlEnabled,
          fileIdToFaces: fileIdToFaces,
          faceIDsToPersonID: faceIDsToPersonID,
          fileIDToImageEmbedding: fileIDToImageEmbedding,
          clipPositiveTextVector: clipPositiveTextVector,
        );

        historicalMemoryResult.add(
          TimeMemory(
            photoSelection,
            day: date,
            date.subtract(kMemoriesMargin).microsecondsSinceEpoch,
            date.add(kDayItself).microsecondsSinceEpoch,
          ),
        );
      } else {
        for (final year in significantDays) {
          final date = DateTime(year, dayMonth ~/ 100, dayMonth % 100);
          final showDate = DateTime(
            currentYear,
            dayMonth ~/ 100,
            dayMonth % 100,
          );
          final files = yearGroups[year]!;
          final photoSelection = await SmartMemoriesService._bestSelection(
            files,
            isLocalGalleryMode: isLocalGalleryMode,
            mlEnabled: mlEnabled,
            fileIdToFaces: fileIdToFaces,
            faceIDsToPersonID: faceIDsToPersonID,
            fileIDToImageEmbedding: fileIDToImageEmbedding,
            clipPositiveTextVector: clipPositiveTextVector,
          );
          historicalMemoryResult.add(
            TimeMemory(
              photoSelection,
              day: date,
              yearsAgo: currentTime.year - date.year,
              showDate.subtract(kMemoriesMargin).microsecondsSinceEpoch,
              showDate.add(kDayItself).microsecondsSinceEpoch,
            ),
          );
        }
      }
    }

    if (historicalMemoryResult.isEmpty) {
      final currentWeekYearGroups = <int, List<Memory>>{};
      for (final file in availableFiles) {
        if (file.creationTime! > cutOffTime.microsecondsSinceEpoch) continue;

        final creationTime = DateTime.fromMicrosecondsSinceEpoch(
          file.creationTime!,
        );
        final week = getWeekNumber(creationTime);
        if (week != currentWeek) continue;
        final year = creationTime.year;

        currentWeekYearGroups
            .putIfAbsent(year, () => [])
            .add(Memory.fromFile(file, seenTimes));
      }

      if (currentWeekYearGroups.isNotEmpty) {
        final significantWeeks = currentWeekYearGroups.entries
            .where((e) => e.value.length > significantWeekThreshold)
            .map((e) => e.key)
            .toList();
        if (significantWeeks.length >= 3) {
          final allPhotos = currentWeekYearGroups.values
              .expand((x) => x)
              .toList();
          final photoSelection = await SmartMemoriesService._bestSelection(
            allPhotos,
            isLocalGalleryMode: isLocalGalleryMode,
            mlEnabled: mlEnabled,
            fileIdToFaces: fileIdToFaces,
            faceIDsToPersonID: faceIDsToPersonID,
            fileIDToImageEmbedding: fileIDToImageEmbedding,
            clipPositiveTextVector: clipPositiveTextVector,
          );
          historicalMemoryResult.add(
            TimeMemory(
              photoSelection,
              currentTime.subtract(kMemoriesMargin).microsecondsSinceEpoch,
              currentTime.add(kMemoriesUpdateFrequency).microsecondsSinceEpoch,
            ),
          );
        } else {
          for (final year in significantWeeks) {
            final date = DateTime(
              year,
              1,
              1,
            ).add(Duration(days: (currentWeek - 1) * 7));
            final files = currentWeekYearGroups[year]!;
            final photoSelection = await SmartMemoriesService._bestSelection(
              files,
              isLocalGalleryMode: isLocalGalleryMode,
              mlEnabled: mlEnabled,
              fileIdToFaces: fileIdToFaces,
              faceIDsToPersonID: faceIDsToPersonID,
              fileIDToImageEmbedding: fileIDToImageEmbedding,
              clipPositiveTextVector: clipPositiveTextVector,
            );
            historicalMemoryResult.add(
              TimeMemory(
                photoSelection,
                yearsAgo: currentTime.year - date.year,
                currentTime.subtract(kMemoriesMargin).microsecondsSinceEpoch,
                currentTime
                    .add(kMemoriesUpdateFrequency)
                    .microsecondsSinceEpoch,
              ),
            );
          }
        }
      }
    }

    const monthSelectionSize = 20;
    final currentMonthYearGroups = <int, List<Memory>>{};
    final historicalMemoryFileIds = <int>{};
    SmartMemoriesService._markUsedMemories(
      historicalMemoryFileIds,
      historicalMemoryResult,
      isLocalGalleryMode: isLocalGalleryMode,
    );
    for (final file in availableFiles) {
      final fileId = SmartMemoriesService._memoryFileId(
        file,
        isLocalGalleryMode: isLocalGalleryMode,
      );
      if (fileId != null && historicalMemoryFileIds.contains(fileId)) {
        continue;
      }
      if (file.creationTime! > cutOffTime.microsecondsSinceEpoch) continue;

      final creationTime = DateTime.fromMicrosecondsSinceEpoch(
        file.creationTime!,
      );
      final month = creationTime.month;
      if (month != currentMonth) continue;
      final year = creationTime.year;

      currentMonthYearGroups
          .putIfAbsent(year, () => [])
          .add(Memory.fromFile(file, seenTimes));
    }

    final sortedYearsForCurrentMonth = currentMonthYearGroups.keys.toList()
      ..sort(
        (a, b) => currentMonthYearGroups[b]!.length.compareTo(
          currentMonthYearGroups[a]!.length,
        ),
      );
    for (int i = 0; i < 2; i++) {
      if (sortedYearsForCurrentMonth.isEmpty) break;
      final year = sortedYearsForCurrentMonth.removeAt(0);
      final monthYearFiles = currentMonthYearGroups[year]!;
      final photoSelection = await SmartMemoriesService._bestSelection(
        monthYearFiles,
        prefferedSize: monthSelectionSize,
        isLocalGalleryMode: isLocalGalleryMode,
        mlEnabled: mlEnabled,
        fileIdToFaces: fileIdToFaces,
        faceIDsToPersonID: faceIDsToPersonID,
        fileIDToImageEmbedding: fileIDToImageEmbedding,
        clipPositiveTextVector: clipPositiveTextVector,
      );
      final daysLeftInMonth =
          DateTime(currentYear, currentMonth + 1, 0).day - currentTime.day + 1;
      historicalMemoryResult.add(
        TimeMemory(
          photoSelection,
          month: DateTime(year, currentMonth),
          yearsAgo: currentTime.year - year,
          currentTime.microsecondsSinceEpoch,
          currentTime
              .add(Duration(days: daysLeftInMonth))
              .microsecondsSinceEpoch,
        ),
      );
    }
    if (sortedYearsForCurrentMonth.length <= 3) {
      return [...recentMemoryResult, ...historicalMemoryResult];
    }
    final allPhotos = sortedYearsForCurrentMonth
        .expand((year) => currentMonthYearGroups[year]!)
        .toList();
    final photoSelection = await SmartMemoriesService._bestSelection(
      allPhotos,
      prefferedSize: monthSelectionSize,
      isLocalGalleryMode: isLocalGalleryMode,
      mlEnabled: mlEnabled,
      fileIdToFaces: fileIdToFaces,
      faceIDsToPersonID: faceIDsToPersonID,
      fileIDToImageEmbedding: fileIDToImageEmbedding,
      clipPositiveTextVector: clipPositiveTextVector,
    );
    final daysLeftInMonth =
        DateTime(currentYear, currentMonth + 1, 0).day - currentTime.day + 1;
    historicalMemoryResult.add(
      TimeMemory(
        photoSelection,
        month: DateTime(currentYear, currentMonth),
        currentTime.microsecondsSinceEpoch,
        currentTime.add(Duration(days: daysLeftInMonth)).microsecondsSinceEpoch,
      ),
    );

    return [...recentMemoryResult, ...historicalMemoryResult];
  }

  static Future<void> _maybeAddRecentTimeMemory(
    List<TimeMemory> memories,
    Iterable<EnteFile> allFiles, {
    required DateTime sourceStart,
    required DateTime sourceEnd,
    required DateTime showStart,
    required DateTime showEnd,
    required TimeMemoryKind kind,
    required bool isLocalGalleryMode,
    required bool mlEnabled,
    required Map<int, int> seenTimes,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Map<String, String> faceIDsToPersonID,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
  }) async {
    final sourceStartMicros = sourceStart.microsecondsSinceEpoch;
    final sourceEndMicros = sourceEnd.microsecondsSinceEpoch;
    final candidates = <Memory>[];
    for (final file in allFiles) {
      final creationTime = file.creationTime;
      if (creationTime == null ||
          creationTime < sourceStartMicros ||
          creationTime >= sourceEndMicros) {
        continue;
      }
      candidates.add(Memory.fromFile(file, seenTimes));
    }

    if (candidates.length < SmartMemoriesService.minimumMemoryLength) {
      return;
    }

    final photoSelection = await SmartMemoriesService._bestSelection(
      candidates,
      prefferedSize: _recentTimeMemorySelectionSize,
      distributionOverride: SelectionDistribution.timeBuckets,
      isLocalGalleryMode: isLocalGalleryMode,
      mlEnabled: mlEnabled,
      fileIdToFaces: fileIdToFaces,
      faceIDsToPersonID: faceIDsToPersonID,
      fileIDToImageEmbedding: fileIDToImageEmbedding,
      clipPositiveTextVector: clipPositiveTextVector,
    );
    memories.add(
      TimeMemory(
        photoSelection,
        showStart.microsecondsSinceEpoch,
        showEnd.microsecondsSinceEpoch,
        kind: kind,
      ),
    );
  }

  static Future<List<FillerMemory>> computeFillerMemories(
    Iterable<EnteFile> allFiles,
    DateTime currentTime, {
    required Map<int, int> seenTimes,
    Map<String, int>? localIdToIntId,
  }) async {
    final List<FillerMemory> memoryResults = [];
    if (allFiles.isEmpty) return [];
    final nowInMicroseconds = currentTime.microsecondsSinceEpoch;
    final windowEnd = currentTime
        .add(kMemoriesUpdateFrequency)
        .microsecondsSinceEpoch;
    final currentYear = currentTime.year;
    final cutOffTime = currentTime.subtract(
      const Duration(days: 364) - kMemoriesUpdateFrequency,
    );
    final timeTillYearEnd = DateTime(currentYear + 1).difference(currentTime);
    final bool almostYearEnd = timeTillYearEnd < kMemoriesUpdateFrequency;

    final Map<int, List<Memory>> yearsAgoToMemories = {};
    for (final file in allFiles) {
      if (file.creationTime! > cutOffTime.microsecondsSinceEpoch) {
        continue;
      }
      final fileDate = DateTime.fromMicrosecondsSinceEpoch(file.creationTime!);
      final fileTimeInYear = fileDate.copyWith(year: currentYear);
      final diff = fileTimeInYear.difference(currentTime);
      if (!diff.isNegative && diff < kMemoriesUpdateFrequency) {
        final yearsAgo = currentYear - fileDate.year;
        yearsAgoToMemories
            .putIfAbsent(yearsAgo, () => [])
            .add(
              Memory.fromFile(
                file,
                seenTimes,
                seenTimeKey: SmartMemoriesService._seenTimeKeyForFile(
                  file,
                  localIdToIntId,
                ),
              ),
            );
      } else if (almostYearEnd) {
        final altDiff = fileDate
            .copyWith(year: currentYear + 1)
            .difference(currentTime);
        if (!altDiff.isNegative && altDiff < kMemoriesUpdateFrequency) {
          final yearsAgo = currentYear - fileDate.year + 1;
          yearsAgoToMemories
              .putIfAbsent(yearsAgo, () => [])
              .add(
                Memory.fromFile(
                  file,
                  seenTimes,
                  seenTimeKey: SmartMemoriesService._seenTimeKeyForFile(
                    file,
                    localIdToIntId,
                  ),
                ),
              );
        }
      }
    }
    for (
      var yearAgo = 1;
      yearAgo <= SmartMemoriesService.yearsBefore;
      yearAgo++
    ) {
      final memories = yearsAgoToMemories[yearAgo];
      if (memories == null) continue;
      memories.sort(
        (a, b) => a.file.creationTime!.compareTo(b.file.creationTime!),
      );
      final fillerMemory = FillerMemory(
        memories,
        yearAgo,
        nowInMicroseconds,
        windowEnd,
      );
      memoryResults.add(fillerMemory);
    }
    return memoryResults;
  }

  static Future<List<OnThisDayMemory>> computeOnThisDayMemories(
    Iterable<EnteFile> allFiles,
    DateTime currentTime, {
    required Map<int, int> seenTimes,
    required Set<int> collectionIDsToExclude,
    Map<String, int>? localIdToIntId,
  }) async {
    final List<OnThisDayMemory> memoryResults = [];
    if (allFiles.isEmpty) return [];

    final daysToCompute = kMemoriesUpdateFrequency.inDays;
    final currentYear = currentTime.year;
    final currentMonth = currentTime.month;
    final currentDay = currentTime.day;
    final startPoint = DateTime(currentYear, currentMonth, currentDay);
    final cutOffTime = startPoint.subtract(
      const Duration(days: 363) - kMemoriesUpdateFrequency,
    );
    final diffThreshold = Duration(days: daysToCompute);

    final Map<int, List<Memory>> daysToMemories = {};
    final Map<int, List<int>> daysToYears = {};

    final timeTillYearEnd = DateTime(currentYear + 1).difference(startPoint);
    final bool almostYearEnd = timeTillYearEnd < diffThreshold;

    for (final file in allFiles) {
      if (collectionIDsToExclude.contains(file.collectionID)) continue;
      if (file.creationTime! > cutOffTime.microsecondsSinceEpoch) {
        continue;
      }
      final fileDate = DateTime.fromMicrosecondsSinceEpoch(file.creationTime!);
      final fileTimeInYear = fileDate.copyWith(year: currentYear);
      final diff = fileTimeInYear.difference(startPoint);
      if (!diff.isNegative && diff < diffThreshold) {
        daysToMemories
            .putIfAbsent(diff.inDays, () => [])
            .add(
              Memory.fromFile(
                file,
                seenTimes,
                seenTimeKey: SmartMemoriesService._seenTimeKeyForFile(
                  file,
                  localIdToIntId,
                ),
              ),
            );
        daysToYears.putIfAbsent(diff.inDays, () => []).add(fileDate.year);
      } else if (almostYearEnd) {
        final altDiff = fileDate
            .copyWith(year: currentYear + 1)
            .difference(currentTime);
        if (!altDiff.isNegative && altDiff < diffThreshold) {
          daysToMemories
              .putIfAbsent(altDiff.inDays, () => [])
              .add(
                Memory.fromFile(
                  file,
                  seenTimes,
                  seenTimeKey: SmartMemoriesService._seenTimeKeyForFile(
                    file,
                    localIdToIntId,
                  ),
                ),
              );
          daysToYears.putIfAbsent(altDiff.inDays, () => []).add(fileDate.year);
        }
      }
    }

    for (var day = 0; day < daysToCompute; day++) {
      final memories = daysToMemories[day];
      if (memories == null) continue;
      if (memories.length < 5) continue;
      final years = daysToYears[day]!;
      if (years.toSet().length < 2) continue;

      final filteredMemories = <Memory>[];
      if (memories.length > 20) {
        final Map<int, List<Memory>> memoriesByYear = {};
        for (final memory in memories) {
          final creationTime = DateTime.fromMicrosecondsSinceEpoch(
            memory.file.creationTime!,
          );
          final year = creationTime.year;
          memoriesByYear.putIfAbsent(year, () => []).add(memory);
        }
        for (final year in memoriesByYear.keys) {
          memoriesByYear[year]!.shuffle(Random());
        }

        List<int> years = memoriesByYear.keys.toList()..sort();
        if (years.length > 20) {
          years.shuffle(Random());
          years = years.take(20).toList()..sort();
        }

        for (final year in years) {
          if (filteredMemories.length >= 20) break;
          final yearMemories = memoriesByYear[year]!;
          if (yearMemories.isNotEmpty) {
            filteredMemories.add(yearMemories.removeAt(0));
          }
        }

        while (filteredMemories.length < 20) {
          bool addedAny = false;
          for (final year in years) {
            if (filteredMemories.length >= 20) break;
            final yearMemories = memoriesByYear[year]!;
            if (yearMemories.isNotEmpty) {
              filteredMemories.add(yearMemories.removeAt(0));
              addedAny = true;
            }
          }
          if (!addedAny) break;
        }
      } else {
        filteredMemories.addAll(memories);
      }

      filteredMemories.sort(
        (a, b) => a.file.creationTime!.compareTo(b.file.creationTime!),
      );
      final onThisDayMemory = OnThisDayMemory(
        filteredMemories,
        startPoint.add(Duration(days: day)).microsecondsSinceEpoch,
        startPoint.add(Duration(days: day + 1)).microsecondsSinceEpoch,
      );
      memoryResults.add(onThisDayMemory);
    }
    return memoryResults;
  }

  static int getWeekNumber(DateTime date) {
    final int dayOfYear = int.parse(DateFormat('D').format(date));
    return ((dayOfYear - 1) ~/ 7) + 1;
  }

  static DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime _startOfWeek(DateTime date) {
    final startOfDay = _startOfDay(date);
    return startOfDay.subtract(Duration(days: startOfDay.weekday - 1));
  }

  static DateTime _startOfMonth(DateTime date) {
    return DateTime(date.year, date.month);
  }
}
