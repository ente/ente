import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/memories/filler_memory.dart";
import "package:photos/models/memories/memories_cache.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/memory_spec.dart";
import "package:photos/models/memories/on_this_day_memory.dart";
import "package:photos/models/memories/people_memory.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/models/memories/time_memory.dart";
import "package:photos/models/memories/trip_memory.dart";

void main() {
  final l10n = lookupAppLocalizations(const Locale("en"));
  final calcTime = DateTime.utc(2026, 3, 26, 8);

  setUpAll(() async {
    await initializeDateFormatting("en");
  });

  EnteFile buildFile(int generatedId, {int? uploadedId, int? creationTime}) {
    final file = EnteFile();
    file.generatedID = generatedId;
    file.uploadedFileID = uploadedId ?? generatedId;
    file.creationTime =
        creationTime ??
        DateTime.utc(2020, 1, generatedId.clamp(1, 28)).microsecondsSinceEpoch;
    file.fileType = FileType.image;
    return file;
  }

  List<Memory> buildMemories(List<int> ids) {
    return ids.map((id) => Memory(buildFile(id), -1)).toList();
  }

  ToShowMemory roundTripEntry(SmartMemory memory) {
    return ToShowMemory.fromJson(
      ToShowMemory.fromSmartMemory(memory, calcTime).toJson(),
    );
  }

  group("legacy cache compatibility", () {
    test("legacy people entries still decode and hydrate", () {
      final cached = ToShowMemory.fromJson({
        "title": "Stored people title",
        "fileUploadedIDs": [101, 102],
        "type": "people",
        "firstTimeToShow": 10,
        "lastTimeToShow": 20,
        "id": "people-legacy",
        "calculationTime": 0,
        "personID": "person-1",
        "personName": "Alex",
        "isUnnamedCluster": false,
        "peopleMemoryType": "spotlight",
      });

      final hydrated = cached.toSmartMemory(buildMemories([101, 102]));

      expect(cached.hasTypedSpec, isFalse);
      expect(hydrated, isA<PeopleMemory>());
      final peopleMemory = hydrated as PeopleMemory;
      expect(peopleMemory.personID, "person-1");
      expect(peopleMemory.personName, "Alex");
      expect(peopleMemory.peopleMemoryType, PeopleMemoryType.spotlight);
      expect(peopleMemory.title, "Stored people title");
    });

    test("legacy non-people entries still hydrate through fallback path", () {
      final cached = ToShowMemory.fromJson({
        "title": "Stored trip title",
        "fileUploadedIDs": [201, 202],
        "type": "trips",
        "firstTimeToShow": 10,
        "lastTimeToShow": 20,
        "id": "trip-legacy",
        "calculationTime": 0,
        "location": {"latitude": 12.34, "longitude": 56.78},
      });

      final hydrated = cached.toSmartMemory(buildMemories([201, 202]));

      expect(cached.hasTypedSpec, isFalse);
      expect(hydrated.runtimeType, SmartMemory);
      expect(hydrated.type, MemoryType.trips);
      expect(hydrated.title, "Stored trip title");
      expect(hydrated.id, "trip-legacy");
    });
  });

  group("typed spec round-trip", () {
    test("typed entries preserve subtype metadata and title semantics", () {
      final tripMemory = TripMemory(
        buildMemories([301, 302]),
        10,
        20,
        const Location(latitude: 48.8566, longitude: 2.3522),
        id: "trip-typed",
        locationName: "Paris",
        tripYear: 2021,
        tripKey: "trip-paris-2021",
      )..title = "Stored trip title";

      final timeMemory = TimeMemory(
        buildMemories([401, 402]),
        30,
        40,
        id: "time-typed",
        kind: TimeMemoryKind.day,
        day: DateTime.utc(2022, 3, 14),
        yearsAgo: 4,
      )..title = "Stored time title";

      final lastWeekMemory = TimeMemory(
        buildMemories([411, 412]),
        41,
        42,
        id: "time-last-week",
        kind: TimeMemoryKind.lastWeek,
      )..title = "Stored last week title";

      final lastMonthMemory = TimeMemory(
        buildMemories([421, 422]),
        43,
        44,
        id: "time-last-month",
        kind: TimeMemoryKind.lastMonth,
      )..title = "Stored last month title";

      final fillerMemory = FillerMemory(
        buildMemories([501]),
        7,
        50,
        60,
        id: "filler-typed",
      )..title = "Stored filler title";

      final onThisDayMemory = OnThisDayMemory(
        buildMemories([601]),
        70,
        80,
        id: "otd-typed",
      )..title = "Stored on this day title";

      final peopleMemory = PeopleMemory(
        buildMemories([701, 702]),
        90,
        100,
        PeopleMemoryType.doingSomethingTogether,
        "person-2",
        "Sam",
        id: "people-typed",
        activity: PeopleActivity.hiking,
      )..title = "Stored people title";

      final originals = <SmartMemory>[
        tripMemory,
        timeMemory,
        lastWeekMemory,
        lastMonthMemory,
        fillerMemory,
        onThisDayMemory,
        peopleMemory,
      ];

      for (final original in originals) {
        final cached = roundTripEntry(original);
        final hydrated = cached.toSmartMemory(original.memories);

        expect(cached.hasTypedSpec, isTrue, reason: original.id);
        expect(hydrated.runtimeType, original.runtimeType, reason: original.id);
        expect(hydrated.id, original.id, reason: original.id);
        expect(hydrated.title, original.title, reason: original.id);
        expect(
          hydrated.createTitle(l10n, "en"),
          original.createTitle(l10n, "en"),
          reason: original.id,
        );
      }
    });

    test("memories cache round-trip preserves typed and legacy entries", () {
      final typedEntry = ToShowMemory.fromSmartMemory(
        TripMemory(
          buildMemories([801, 802]),
          100,
          200,
          const Location(latitude: 40.7128, longitude: -74.006),
          id: "trip-cache",
          locationName: "New York",
          tripYear: 2020,
          tripKey: "trip-nyc-2020",
        )..title = "Stored typed trip title",
        calcTime,
      );

      final legacyEntry = ToShowMemory.fromJson({
        "title": "Stored legacy trip title",
        "fileUploadedIDs": [901],
        "type": "trips",
        "firstTimeToShow": 10,
        "lastTimeToShow": 20,
        "id": "trip-legacy-cache",
        "calculationTime": 0,
        "location": {"latitude": 1.23, "longitude": 4.56},
      });

      final cache = MemoriesCache(
        toShowMemories: [typedEntry, legacyEntry],
        peopleShownLogs: [],
        clipShownLogs: [],
        tripsShownLogs: [],
        baseLocations: [],
      );

      final decoded = MemoriesCache.decodeFromJsonString(
        MemoriesCache.encodeToJsonString(cache),
      );

      expect(decoded.toShowMemories, hasLength(2));
      expect(decoded.toShowMemories.first.hasTypedSpec, isTrue);
      expect(decoded.toShowMemories.last.hasTypedSpec, isFalse);
      expect(decoded.toShowMemories.first.id, "trip-cache");
      expect(decoded.toShowMemories.last.id, "trip-legacy-cache");
      expect(decoded.toShowMemories.first.tripKey, "trip-nyc-2020");
    });

    test("legacy time specs infer the correct subtype", () {
      final legacyWeekSpec = TimeMemorySpec.fromJson({
        "kind": "time",
        "yearsAgo": 2,
      });
      final legacyMonthSpec = TimeMemorySpec.fromJson({
        "kind": "time",
        "month": DateTime.utc(2021, 3, 1).microsecondsSinceEpoch,
      });

      expect(legacyWeekSpec.timeKind, TimeMemoryKind.week);
      expect(legacyMonthSpec.timeKind, TimeMemoryKind.month);

      final legacyWeekMemory = legacyWeekSpec.toSmartMemory(
        buildMemories([1001]),
        firstDateToShow: 10,
        lastDateToShow: 20,
        title: "legacy-week",
        id: "legacy-week",
      );
      final legacyMonthMemory = legacyMonthSpec.toSmartMemory(
        buildMemories([1002]),
        firstDateToShow: 10,
        lastDateToShow: 20,
        title: "legacy-month",
        id: "legacy-month",
      );

      expect(
        legacyWeekMemory.createTitle(l10n, "en"),
        l10n.thisWeekXYearsAgo(count: 2),
      );
      expect(
        legacyMonthMemory.createTitle(l10n, "en"),
        l10n.throughTheYears(dateFormat: "March"),
      );
    });
  });
}
