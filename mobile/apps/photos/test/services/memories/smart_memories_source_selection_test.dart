import "package:flutter_test/flutter_test.dart";
import "package:ml_linalg/vector.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/memories/clip_memory.dart";
import "package:photos/models/memories/filler_memory.dart";
import "package:photos/models/memories/memories_cache.dart";
import "package:photos/models/memories/smart_memory_constants.dart";
import "package:photos/models/memories/time_memory.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/services/location_service.dart";
import "package:photos/services/smart_memories_service.dart";
import "package:timezone/data/latest.dart" as tzdata;
import "package:timezone/timezone.dart" as timezone;

EnteFile _file({
  required int id,
  required DateTime createdAt,
  Location? location,
}) {
  final file = EnteFile()
    ..uploadedFileID = id
    ..generatedID = id
    ..creationTime = createdAt.microsecondsSinceEpoch
    ..fileType = FileType.image;
  if (location != null) {
    file.location = location;
  }
  return file;
}

Vector get _positiveTextVector => Vector.fromList([1.0]);

Vector _normalizedVector(List<double> values) {
  final vector = Vector.fromList(values);
  final norm = vector.norm();
  return Vector.fromList(values.map((value) => value / norm).toList());
}

void main() {
  group("smart memories source selection", () {
    test(
      "TripMemoriesCalculatorV2 surfaces a trip from the full source set",
      () async {
        const tripLocation = Location(latitude: 48.8566, longitude: 2.3522);
        final currentTime = DateTime.utc(2026, 4, 10);
        final fullSourceFiles = <EnteFile>[
          for (int i = 0; i < 20; i++)
            _file(
              id: i + 1,
              createdAt: DateTime.utc(2024, 1, 10 + (i ~/ 7), 8 + (i % 7) * 2),
              location: tripLocation,
            ),
        ];
        final depletedRemainingFiles = fullSourceFiles.take(6).toList();
        final allFileIdsToFile = {
          for (final file in fullSourceFiles) file.uploadedFileID!: file,
        };
        final citySearchIndex = CitySearchIndex(
          cities: [
            City.fromMap({
              "city": "Paris",
              "country": "France",
              "lat": tripLocation.latitude,
              "lng": tripLocation.longitude,
            }),
          ],
          nodes: const [
            [0, -1, -1, 0],
          ],
          root: 0,
          maxLatDelta: 1,
          maxLngDelta: 1,
        );

        final (fullTrips, _) = await TripMemoriesCalculatorV2.compute(
          fullSourceFiles,
          allFileIdsToFile,
          currentTime,
          <TripsShownLog>[],
          surfaceAll: true,
          cachedTripMemories: const <ToShowMemory>[],
          isLocalGalleryMode: false,
          mlEnabled: true,
          seenTimes: const <int, int>{},
          fileIdToFaces: const <int, List<FaceWithoutEmbedding>>{},
          faceIDsToPersonID: const <String, String>{},
          fileIDToImageEmbedding: const <int, EmbeddingVector>{},
          clipPositiveTextVector: _positiveTextVector,
          citySearchIndex: citySearchIndex,
        );

        final (remainingTrips, _) = await TripMemoriesCalculatorV2.compute(
          depletedRemainingFiles,
          allFileIdsToFile,
          currentTime,
          <TripsShownLog>[],
          surfaceAll: true,
          cachedTripMemories: const <ToShowMemory>[],
          isLocalGalleryMode: false,
          mlEnabled: true,
          seenTimes: const <int, int>{},
          fileIdToFaces: const <int, List<FaceWithoutEmbedding>>{},
          faceIDsToPersonID: const <String, String>{},
          fileIDToImageEmbedding: const <int, EmbeddingVector>{},
          clipPositiveTextVector: _positiveTextVector,
          citySearchIndex: citySearchIndex,
        );

        expect(fullTrips, hasLength(1));
        expect(fullTrips.first.memories, hasLength(10));
        expect(fullTrips.first.locationName, "Paris");
        expect(remainingTrips, isEmpty);
      },
    );

    test(
      "TimeMemoriesCalculator uses the recent source without historical candidates",
      () async {
        final currentTime = DateTime.utc(2026, 4, 10);
        final fullRecentSource = <EnteFile>[
          for (int dayOffset = 0; dayOffset < 5; dayOffset++)
            for (int photoIndex = 0; photoIndex < 4; photoIndex++)
              _file(
                id: dayOffset * 10 + photoIndex + 1,
                createdAt: DateTime.utc(2026, 4, 1 + dayOffset, 9 + photoIndex),
              ),
        ];
        final memories = await TimeMemoriesCalculator.computeTimeMemories(
          const <EnteFile>[],
          currentTime,
          recentSourceFiles: fullRecentSource,
          isLocalGalleryMode: false,
          mlEnabled: true,
          seenTimes: const <int, int>{},
          fileIdToFaces: const <int, List<FaceWithoutEmbedding>>{},
          faceIDsToPersonID: const <String, String>{},
          fileIDToImageEmbedding: const <int, EmbeddingVector>{},
          clipPositiveTextVector: _positiveTextVector,
        );

        final lastWeekMemory = memories.firstWhere(
          (memory) => memory.kind == TimeMemoryKind.lastWeek,
        );
        final distinctDays = lastWeekMemory.memories
            .map(
              (memory) => DateTime.fromMicrosecondsSinceEpoch(
                memory.file.creationTime!,
              ).day,
            )
            .toSet();

        expect(lastWeekMemory.memories, hasLength(10));
        expect(distinctDays.length, greaterThanOrEqualTo(4));
      },
    );

    test("MemoryFileIndex merges ranges and preserves descending order", () {
      final index = MemoryFileIndex([
        _file(id: 2, createdAt: DateTime(2024, 1, 2)),
        _file(id: 4, createdAt: DateTime(2024, 1, 4)),
        _file(id: 1, createdAt: DateTime(2024, 1, 1)),
        _file(id: 3, createdAt: DateTime(2024, 1, 3)),
      ]);

      final files = index.filesInDateRanges([
        (start: DateTime(2024, 1, 1), end: DateTime(2024, 1, 3)),
        (start: DateTime(2024, 1, 2), end: DateTime(2024, 1, 4)),
      ]);

      expect(files.map((file) => file.uploadedFileID), [3, 2, 1]);
    });

    test(
      "MemoryFileIndex is a broad prefilter for exact date windows",
      () async {
        final currentTime = DateTime(2026, 8, 18, 12);
        final source = [
          _file(id: 1, createdAt: DateTime(2025, 8, 18, 10)),
          _file(id: 2, createdAt: DateTime(2025, 8, 18, 14)),
          _file(id: 3, createdAt: DateTime(2025, 8, 21, 11)),
          _file(id: 4, createdAt: DateTime(2025, 9, 1)),
        ];
        final indexedCandidates = MemoryFileIndex(
          source,
        ).filesForCalendar(monthDays: const {818, 819, 820, 821});

        final fullResult = await TimeMemoriesCalculator.computeFillerMemories(
          source,
          currentTime,
          seenTimes: const <int, int>{},
        );
        final indexedResult =
            await TimeMemoriesCalculator.computeFillerMemories(
              indexedCandidates,
              currentTime,
              seenTimes: const <int, int>{},
            );

        Iterable<int?> selectedIDs(List<FillerMemory> memories) => memories
            .expand((memory) => memory.memories)
            .map((memory) => memory.file.uploadedFileID);
        expect(selectedIDs(indexedResult), selectedIDs(fullResult));
        expect(selectedIDs(indexedResult), [2, 3]);
      },
    );

    test(
      "Filler memories preserve year-boundary, leap-day, and time-window matching",
      () async {
        final yearBoundaryMemories =
            await TimeMemoriesCalculator.computeFillerMemories(
              [
                _file(id: 1, createdAt: DateTime.utc(2025, 12, 31)),
                _file(id: 2, createdAt: DateTime.utc(2025, 1, 1)),
                _file(id: 3, createdAt: DateTime.utc(2025, 1, 3)),
              ],
              DateTime.utc(2026, 12, 31),
              seenTimes: const <int, int>{},
            );

        expect(
          yearBoundaryMemories
              .singleWhere((memory) => memory.yearsAgo == 1)
              .memories
              .map((memory) => memory.file.uploadedFileID),
          [1],
        );
        expect(
          yearBoundaryMemories
              .singleWhere((memory) => memory.yearsAgo == 2)
              .memories
              .map((memory) => memory.file.uploadedFileID),
          [2],
        );
        expect(
          yearBoundaryMemories
              .expand((memory) => memory.memories)
              .map((memory) => memory.file.uploadedFileID),
          isNot(contains(3)),
        );

        final leapDayMemories =
            await TimeMemoriesCalculator.computeFillerMemories(
              [_file(id: 4, createdAt: DateTime.utc(2024, 2, 29))],
              DateTime.utc(2025, 3, 1),
              seenTimes: const <int, int>{},
            );
        expect(leapDayMemories.single.yearsAgo, 1);
        expect(leapDayMemories.single.memories.single.file.uploadedFileID, 4);

        final sameDayMemories =
            await TimeMemoriesCalculator.computeFillerMemories(
              [
                _file(id: 5, createdAt: DateTime(2025, 8, 18, 10)),
                _file(id: 6, createdAt: DateTime(2025, 8, 18, 14)),
                _file(id: 7, createdAt: DateTime(2025, 8, 21, 11)),
              ],
              DateTime(2026, 8, 18, 12),
              seenTimes: const <int, int>{},
            );
        expect(
          sameDayMemories.single.memories.map(
            (memory) => memory.file.uploadedFileID,
          ),
          [6, 7],
        );
      },
    );

    test("historical prefilter covers a DST-expanded date window", () {
      tzdata.initializeTimeZones();
      final location = timezone.getLocation("America/New_York");
      final currentTime = timezone.TZDateTime(location, 2026, 3, 7, 23, 30);

      expect(
        currentTime.add(kMemoriesUpdateFrequency),
        timezone.TZDateTime(location, 2026, 3, 11, 0, 30),
      );
      expect(
        TimeMemoriesCalculator.historicalDayCandidates(currentTime),
        contains(311),
      );
    });

    test("memory week numbers retain seven-day buckets", () {
      expect(TimeMemoriesCalculator.getWeekNumber(DateTime.utc(2024, 1, 1)), 1);
      expect(TimeMemoriesCalculator.getWeekNumber(DateTime.utc(2024, 1, 7)), 1);
      expect(TimeMemoriesCalculator.getWeekNumber(DateTime.utc(2024, 1, 8)), 2);
      expect(
        TimeMemoriesCalculator.getWeekNumber(DateTime.utc(2024, 12, 31)),
        53,
      );
    });

    test(
      "ClipMemoriesCalculator surfaces a memory from the full source set",
      () async {
        final currentTime = DateTime.utc(2026, 4, 10);
        final fullSourceFiles = <EnteFile>[
          for (int i = 0; i < 12; i++)
            _file(
              id: i + 1,
              createdAt: DateTime.utc(2024, 6, 1 + (i ~/ 4), 9 + i),
            ),
        ];
        final depletedRemainingFiles = fullSourceFiles.take(6).toList();
        final selectedClipType = ClipMemoryType.values.first;
        final queryVector = _normalizedVector(
          List<double>.filled(fullSourceFiles.length, 1.0),
        );
        final fileIDToImageEmbedding = <int, EmbeddingVector>{
          for (int i = 0; i < fullSourceFiles.length; i++)
            fullSourceFiles[i].uploadedFileID!: EmbeddingVector(
              fileID: fullSourceFiles[i].uploadedFileID!,
              embedding: List<double>.generate(
                fullSourceFiles.length,
                (index) => index == i ? 1.0 : 0.0,
              ),
            ),
        };

        final fullClipMemories = await ClipMemoriesCalculator.compute(
          fullSourceFiles,
          currentTime,
          <ClipShownLog>[],
          surfaceAll: true,
          isLocalGalleryMode: false,
          seenTimes: const <int, int>{},
          fileIDToImageEmbedding: fileIDToImageEmbedding,
          clipMemoryTypeVectors: <ClipMemoryType, Vector>{
            selectedClipType: queryVector,
          },
        );

        final depletedClipMemories = await ClipMemoriesCalculator.compute(
          depletedRemainingFiles,
          currentTime,
          <ClipShownLog>[],
          surfaceAll: true,
          isLocalGalleryMode: false,
          seenTimes: const <int, int>{},
          fileIDToImageEmbedding: fileIDToImageEmbedding,
          clipMemoryTypeVectors: <ClipMemoryType, Vector>{
            selectedClipType: queryVector,
          },
        );

        expect(fullClipMemories, hasLength(1));
        expect(fullClipMemories.first.memories, hasLength(10));
        expect(depletedClipMemories, isEmpty);
      },
    );
  });
}
