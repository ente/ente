import "package:flutter_test/flutter_test.dart";
import "package:photos/services/memory_lane/memory_lane_service.dart";

Map<String, dynamic> _buildFace(
  String faceId,
  int fileId,
  DateTime creationDate, {
  double score = 0.9,
  double blur = 50.0,
}) {
  return {
    "faceId": faceId,
    "fileId": fileId,
    "creationTime": creationDate.microsecondsSinceEpoch,
    "year": creationDate.year,
    "score": score,
    "blur": blur,
  };
}

void main() {
  group("Memory lane selection", () {
    test("returns ready when at least five eligible years are present", () {
      final faces = <Map<String, dynamic>>[];
      for (int year = 2010; year < 2015; year++) {
        for (int index = 0; index < 5; index++) {
          faces.add(
            _buildFace(
              "face-$year-$index",
              year * 10 + index,
              DateTime(year, 1, 1).add(Duration(days: index * 60)),
            ),
          );
        }
      }

      final result = selectTimelineEntriesTask({
        "faces": faces,
        "minYears": 5,
        "minFaces": 4,
      });

      expect(result["status"], equals("ready"));
      final years = (result["years"] as List<dynamic>).cast<int>();
      expect(years, equals(List<int>.generate(5, (i) => 2010 + i)));

      final entries = (result["entries"] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(entries.length, equals(20));
      final faceIds = entries.map((entry) => entry["faceId"]).toSet();
      expect(faceIds.length, equals(entries.length));

      for (final year in years) {
        final yearEntries = entries
            .where((entry) => entry["year"] == year)
            .toList();
        expect(yearEntries.length, equals(4));
      }
    });

    test("returns ineligible when fewer than five years qualify", () {
      final faces = <Map<String, dynamic>>[];
      for (int year = 2011; year < 2015; year++) {
        for (int index = 0; index < 4; index++) {
          faces.add(
            _buildFace(
              "face-$year-$index",
              year * 100 + index,
              DateTime(year, 3, 1).add(Duration(days: index * 40)),
            ),
          );
        }
      }

      final result = selectTimelineEntriesTask({
        "faces": faces,
        "minYears": 5,
        "minFaces": 4,
      });

      expect(result["status"], equals("ineligible"));
      expect(result["eligibleYearCount"], equals(4));
      expect(result["entries"], isNull);
    });

    test("prefers higher quality faces within a year", () {
      final baseDate = DateTime(2020, 1, 1);
      final faces = <Map<String, dynamic>>[
        _buildFace(
          "low-score",
          1,
          baseDate.add(const Duration(days: 1)),
          score: 0.6,
          blur: 20,
        ),
        _buildFace(
          "high-resolution",
          2,
          baseDate.add(const Duration(days: 2)),
          score: 0.85,
          blur: 40,
        ),
        _buildFace(
          "sharp-and-high-score",
          3,
          baseDate.add(const Duration(days: 3)),
          score: 0.95,
          blur: 80,
        ),
        _buildFace(
          "backup-1",
          4,
          baseDate.add(const Duration(days: 4)),
          score: 0.82,
          blur: 30,
        ),
        _buildFace(
          "backup-2",
          5,
          baseDate.add(const Duration(days: 5)),
          score: 0.81,
          blur: 25,
        ),
      ];

      final result = selectTimelineEntriesTask({
        "faces": faces,
        "minYears": 1,
        "minFaces": 4,
      });

      expect(result["status"], equals("ready"));
      final entries = (result["entries"] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final faceIds = entries.map((entry) => entry["faceId"]).toList();
      expect(
        faceIds,
        containsAll(<String>["sharp-and-high-score", "high-resolution"]),
      );
      expect(faceIds.length, equals(4));
      expect(faceIds, isNot(contains("low-score")));
    });

    test("avoids selecting multiple faces from the same day when possible", () {
      final baseDate = DateTime(2021, 5, 20);
      final faces = <Map<String, dynamic>>[
        _buildFace("day-1-face-1", 101, baseDate),
        _buildFace(
          "day-1-face-2",
          102,
          baseDate.add(const Duration(hours: 5)),
          score: 0.92,
        ),
        _buildFace("day-2-face", 103, baseDate.add(const Duration(days: 1))),
        _buildFace("day-3-face", 104, baseDate.add(const Duration(days: 2))),
        _buildFace("day-4-face", 105, baseDate.add(const Duration(days: 3))),
      ];

      final result = selectTimelineEntriesTask({
        "faces": faces,
        "minYears": 1,
        "minFaces": 4,
      });

      expect(result["status"], equals("ready"));
      final entries = (result["entries"] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final dayKeys = entries
          .map(
            (entry) => DateTime.fromMicrosecondsSinceEpoch(
              entry["creationTime"] as int,
            ),
          )
          .map((date) => DateTime(date.year, date.month, date.day))
          .toSet();
      expect(entries.length, equals(4));
      expect(dayKeys.length, equals(4));
    });

    test(
      "allows duplicate days only when fewer than four unique days are available",
      () {
        final baseDate = DateTime(2022, 3, 10);
        final faces = <Map<String, dynamic>>[
          _buildFace("day-1-a", 201, baseDate, score: 0.95, blur: 70),
          _buildFace(
            "day-1-b",
            202,
            baseDate.add(const Duration(hours: 6)),
            score: 0.9,
            blur: 65,
          ),
          _buildFace(
            "day-2",
            203,
            baseDate.add(const Duration(days: 1)),
            score: 0.93,
            blur: 60,
          ),
          _buildFace(
            "day-3",
            204,
            baseDate.add(const Duration(days: 2)),
            score: 0.91,
            blur: 62,
          ),
        ];

        final result = selectTimelineEntriesTask({
          "faces": faces,
          "minYears": 1,
          "minFaces": 4,
        });

        expect(result["status"], equals("ready"));
        final entries = (result["entries"] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(entries.length, equals(4));
        final normalizedDays = entries
            .map(
              (entry) => DateTime.fromMicrosecondsSinceEpoch(
                entry["creationTime"] as int,
              ),
            )
            .map((date) => DateTime(date.year, date.month, date.day))
            .toList();
        final dayCounts = <DateTime, int>{};
        for (final day in normalizedDays) {
          dayCounts.update(day, (value) => value + 1, ifAbsent: () => 1);
        }
        expect(dayCounts.keys.length, equals(3));
        expect(dayCounts.values.any((count) => count > 1), isTrue);
      },
    );

    test("excludes faces captured before minimum creation time", () {
      final faces = <Map<String, dynamic>>[];
      for (int year = 2008; year < 2017; year++) {
        for (int index = 0; index < 4; index++) {
          faces.add(
            _buildFace(
              "face-$year-$index",
              year * 1000 + index,
              DateTime(year, index + 1, 1),
            ),
          );
        }
      }

      final cutoff = DateTime(2010, 1, 1).microsecondsSinceEpoch;
      final result = selectTimelineEntriesTask({
        "faces": faces,
        "minYears": 5,
        "minFaces": 4,
        "minCreationTime": cutoff,
      });

      expect(result["status"], equals("ready"));
      final years = (result["years"] as List<dynamic>).cast<int>();
      expect(years.first, equals(2010));
      expect(years.length, equals(7));
      expect(years, isNot(contains(2008)));
      expect(years, isNot(contains(2009)));
    });

    test("minimum creation time affects eligibility counts", () {
      final faces = <Map<String, dynamic>>[];
      for (int year = 2012; year < 2018; year++) {
        for (int index = 0; index < 4; index++) {
          faces.add(
            _buildFace(
              "face-$year-$index",
              year * 10 + index,
              DateTime(year, 6, 1).add(Duration(days: index * 30)),
            ),
          );
        }
      }

      final cutoff = DateTime(2014, 1, 1).microsecondsSinceEpoch;
      final result = selectTimelineEntriesTask({
        "faces": faces,
        "minYears": 5,
        "minFaces": 4,
        "minCreationTime": cutoff,
      });

      expect(result["status"], equals("ineligible"));
      expect(result["eligibleYearCount"], equals(4));
      expect(result["entries"], isNull);
    });
  });

  group("minimum eligible creation time", () {
    test("returns null when birthdate missing", () {
      expect(MemoryLaneService.minimumEligibleCreationTimeMicros(null), isNull);
      expect(MemoryLaneService.minimumEligibleCreationTimeMicros(""), isNull);
    });

    test("returns null for invalid birthdate string", () {
      expect(
        MemoryLaneService.minimumEligibleCreationTimeMicros("invalid"),
        isNull,
      );
    });

    test("computes third birthday cutoff", () {
      final birthDate = DateTime(2010, 6, 15);
      final cutoff = MemoryLaneService.minimumEligibleCreationTimeMicros(
        "2010-06-15",
      );
      final expected = DateTime(
        birthDate.year + 3,
        birthDate.month,
        birthDate.day,
      ).microsecondsSinceEpoch;
      expect(cutoff, equals(expected));
    });

    test("clamps day for leap birthdays", () {
      final cutoff = MemoryLaneService.minimumEligibleCreationTimeMicros(
        "2012-02-29",
      );
      final expected = DateTime(2015, 2, 28).microsecondsSinceEpoch;
      expect(cutoff, equals(expected));
    });
  });
}
