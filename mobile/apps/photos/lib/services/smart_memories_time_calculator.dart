part of "smart_memories_service.dart";

class TimeMemoriesCalculator {
  static const _recentTimeMemorySelectionSize = 10;

  static Future<List<TimeMemory>> computeTimeMemories(
    Iterable<EnteFile> allFiles,
    DateTime currentTime, {
    Iterable<EnteFile>? recentSourceFiles,
    int? totalAvailableFileCount,
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
    final recentCandidates = recentSourceFiles ?? availableFiles;
    if (availableFiles.isEmpty && recentCandidates.isEmpty) return [];

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

    final currentWeek = getWeekNumber(currentTime);
    final currentMonth = currentTime.month;
    final currentYear = currentTime.year;
    final cutOffTime = currentTime.subtract(const Duration(days: 365));
    final averageDailyPhotos =
        (totalAvailableFileCount ?? availableFiles.length) / 365;
    final significantDayThreshold = averageDailyPhotos * 0.25;
    final significantWeekThreshold = averageDailyPhotos * 0.40;

    final dayMonthYearGroups = <int, Map<int, List<Memory>>>{};
    final currentWeekYearGroups = <int, List<Memory>>{};
    final currentMonthYearGroups = <int, List<Memory>>{};
    final timeMemoryShowDates = _timeMemoryShowDates(currentTime);

    for (final file in availableFiles) {
      if (file.creationTime! > cutOffTime.microsecondsSinceEpoch) continue;

      final creationTime = DateTime.fromMicrosecondsSinceEpoch(
        file.creationTime!,
      );
      final dayMonth = creationTime.month * 100 + creationTime.day;
      final year = creationTime.year;

      if (timeMemoryShowDates.containsKey(dayMonth)) {
        dayMonthYearGroups
            .putIfAbsent(dayMonth, () => {})
            .putIfAbsent(year, () => [])
            .add(Memory.fromFile(file, seenTimes));
      }
      if (getWeekNumber(creationTime) == currentWeek) {
        currentWeekYearGroups
            .putIfAbsent(year, () => [])
            .add(Memory.fromFile(file, seenTimes));
      }
      if (creationTime.month == currentMonth) {
        currentMonthYearGroups
            .putIfAbsent(year, () => [])
            .add(Memory.fromFile(file, seenTimes));
      }
    }

    for (final dayMonth in dayMonthYearGroups.keys) {
      final month = dayMonth ~/ 100;
      final day = dayMonth % 100;
      final showDate = timeMemoryShowDates[dayMonth]!;

      final yearGroups = dayMonthYearGroups[dayMonth]!;
      final significantDays = yearGroups.entries
          .where((e) => e.value.length > significantDayThreshold)
          .map((e) => e.key)
          .toList();

      if (significantDays.length >= 3) {
        final titleDate = DateTime(significantDays.first, month, day);
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
            day: titleDate,
            showDate.subtract(kMemoriesMargin).microsecondsSinceEpoch,
            showDate.add(kDayItself).microsecondsSinceEpoch,
          ),
        );
      } else {
        for (final year in significantDays) {
          final date = DateTime(year, month, day);
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
              yearsAgo: showDate.year - date.year,
              showDate.subtract(kMemoriesMargin).microsecondsSinceEpoch,
              showDate.add(kDayItself).microsecondsSinceEpoch,
            ),
          );
        }
      }
    }

    if (historicalMemoryResult.isEmpty) {
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
    final historicalMemoryFileIds = <int>{};
    SmartMemoriesService._markUsedMemories(
      historicalMemoryFileIds,
      historicalMemoryResult,
      isLocalGalleryMode: isLocalGalleryMode,
    );
    currentMonthYearGroups.removeWhere((_, memories) {
      memories.removeWhere((memory) {
        final fileId = SmartMemoriesService._memoryFileIdFromMemory(
          memory,
          isLocalGalleryMode: isLocalGalleryMode,
        );
        return fileId != null && historicalMemoryFileIds.contains(fileId);
      });
      return memories.isEmpty;
    });

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

  static DateTime _nextOccurrence(DateTime currentTime, int month, int day) {
    DateTime occurrenceIn(int year) {
      final lastDayOfMonth = DateTime.utc(year, month + 1, 0).day;
      final occurrenceDay = min(day, lastDayOfMonth);
      return currentTime.isUtc
          ? DateTime.utc(year, month, occurrenceDay)
          : DateTime(year, month, occurrenceDay);
    }

    var occurrence = occurrenceIn(currentTime.year);
    if (_calendarDayDifference(currentTime, occurrence) < 0) {
      occurrence = occurrenceIn(currentTime.year + 1);
    }
    return occurrence;
  }

  static int _calendarDayDifference(DateTime start, DateTime end) {
    final startDate = DateTime.utc(start.year, start.month, start.day);
    final endDate = DateTime.utc(end.year, end.month, end.day);
    return endDate.difference(startDate).inDays;
  }

  static Map<int, DateTime> _timeMemoryShowDates(DateTime currentTime) {
    final showDates = <int, DateTime>{};
    for (var month = 1; month <= 12; month++) {
      final daysInMonth = DateTime.utc(2024, month + 1, 0).day;
      for (var day = 1; day <= daysInMonth; day++) {
        final showDate = _nextOccurrence(currentTime, month, day);
        if (_calendarDayDifference(currentTime, showDate) <=
            kMemoriesUpdateFrequency.inDays) {
          showDates[month * 100 + day] = showDate;
        }
      }
    }
    return showDates;
  }

  static List<EnteFile> _filesForHistoricalWindow(
    MemoryFileIndex fileIndex,
    DateTime currentTime,
  ) {
    return fileIndex.filesForCalendar(
      monthDays: historicalDayCandidates(currentTime),
    );
  }

  static List<EnteFile> _filesForTimeMemories(
    MemoryFileIndex fileIndex,
    DateTime currentTime,
  ) {
    return fileIndex.filesForCalendar(
      monthDays: _timeMemoryShowDates(currentTime).keys.toSet(),
      month: currentTime.month,
      week: getWeekNumber(currentTime),
    );
  }

  static List<EnteFile> _filesForRecentTimeMemories(
    MemoryFileIndex fileIndex,
    DateTime currentTime,
  ) {
    final startOfCurrentWeek = _startOfWeek(currentTime);
    final startOfCurrentMonth = _startOfMonth(currentTime);
    return fileIndex.filesInDateRanges([
      (
        start: startOfCurrentWeek.subtract(const Duration(days: 7)),
        end: startOfCurrentWeek,
      ),
      (
        start: DateTime(
          startOfCurrentMonth.year,
          startOfCurrentMonth.month - 1,
        ),
        end: startOfCurrentMonth,
      ),
    ]);
  }

  @visibleForTesting
  static Set<int> historicalDayCandidates(DateTime currentTime) {
    final candidates = <int>{};
    final windowEnd = currentTime.add(kMemoriesUpdateFrequency);
    var targetDate = DateTime.utc(
      currentTime.year,
      currentTime.month,
      currentTime.day,
    );
    final endDate = DateTime.utc(
      windowEnd.year,
      windowEnd.month,
      windowEnd.day,
    );
    while (!targetDate.isAfter(endDate)) {
      candidates.add(targetDate.month * 100 + targetDate.day);
      if (!_isLeapYear(targetDate.year) &&
          targetDate.month == DateTime.march &&
          targetDate.day == 1) {
        candidates.add(DateTime.february * 100 + 29);
      }
      targetDate = DateTime.utc(
        targetDate.year,
        targetDate.month,
        targetDate.day + 1,
      );
    }
    return candidates;
  }

  static ({int dayOffset, int targetYear})? _historicalDateMatch(
    DateTime fileDate,
    DateTime currentTime,
  ) {
    final currentYearDiff = fileDate
        .copyWith(year: currentTime.year)
        .difference(currentTime);
    if (!currentYearDiff.isNegative &&
        currentYearDiff < kMemoriesUpdateFrequency) {
      return (dayOffset: currentYearDiff.inDays, targetYear: currentTime.year);
    }

    final timeTillYearEnd = DateTime(
      currentTime.year + 1,
    ).difference(currentTime);
    if (timeTillYearEnd >= kMemoriesUpdateFrequency) return null;

    final nextYearDiff = fileDate
        .copyWith(year: currentTime.year + 1)
        .difference(currentTime);
    if (!nextYearDiff.isNegative && nextYearDiff < kMemoriesUpdateFrequency) {
      return (dayOffset: nextYearDiff.inDays, targetYear: currentTime.year + 1);
    }
    return null;
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
    final cutOffTime = currentTime.subtract(
      const Duration(days: 364) - kMemoriesUpdateFrequency,
    );
    final historicalCandidates = historicalDayCandidates(currentTime);

    final Map<int, List<Memory>> yearsAgoToMemories = {};
    for (final file in allFiles) {
      if (file.creationTime! > cutOffTime.microsecondsSinceEpoch) {
        continue;
      }
      final fileDate = DateTime.fromMicrosecondsSinceEpoch(file.creationTime!);
      if (!historicalCandidates.contains(fileDate.month * 100 + fileDate.day)) {
        continue;
      }
      final dayMatch = _historicalDateMatch(fileDate, currentTime);
      if (dayMatch == null) continue;
      final yearsAgo = dayMatch.targetYear - fileDate.year;
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
    final historicalCandidates = historicalDayCandidates(startPoint);

    final Map<int, List<Memory>> daysToMemories = {};
    final Map<int, Set<int>> daysToYears = {};

    for (final file in allFiles) {
      if (collectionIDsToExclude.contains(file.collectionID)) continue;
      if (file.creationTime! > cutOffTime.microsecondsSinceEpoch) {
        continue;
      }
      final fileDate = DateTime.fromMicrosecondsSinceEpoch(file.creationTime!);
      if (!historicalCandidates.contains(fileDate.month * 100 + fileDate.day)) {
        continue;
      }
      final dayMatch = _historicalDateMatch(fileDate, startPoint);
      if (dayMatch == null) continue;
      daysToMemories
          .putIfAbsent(dayMatch.dayOffset, () => [])
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
      daysToYears.putIfAbsent(dayMatch.dayOffset, () => {}).add(fileDate.year);
    }

    for (var day = 0; day < daysToCompute; day++) {
      final memories = daysToMemories[day];
      if (memories == null) continue;
      if (memories.length < 5) continue;
      final years = daysToYears[day]!;
      if (years.length < 2) continue;

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
    const daysBeforeMonth = [
      0,
      31,
      59,
      90,
      120,
      151,
      181,
      212,
      243,
      273,
      304,
      334,
    ];
    final leapDay = _isLeapYear(date.year) && date.month > DateTime.february
        ? 1
        : 0;
    final dayOfYear = daysBeforeMonth[date.month - 1] + date.day + leapDay;
    return ((dayOfYear - 1) ~/ 7) + 1;
  }

  static bool _isLeapYear(int year) =>
      year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

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
