import "package:flutter_test/flutter_test.dart";
import "package:photos/services/memory_lane/memory_lane_service.dart";

void main() {
  group("MemoryLaneService date math", () {
    test("completedYearsBetween counts only completed birthdays", () {
      expect(
        MemoryLaneService.completedYearsBetween(
          DateTime(2010, 10, 15),
          DateTime(2015, 10, 14),
        ),
        4,
      );
      expect(
        MemoryLaneService.completedYearsBetween(
          DateTime(2010, 10, 15),
          DateTime(2015, 10, 15),
        ),
        5,
      );
      expect(
        MemoryLaneService.completedYearsBetween(
          DateTime(2010, 10, 15),
          DateTime(2015, 12, 31),
        ),
        5,
      );
    });

    test("completedYearsBetween matches leap-day cutoff behavior", () {
      expect(
        MemoryLaneService.completedYearsBetween(
          DateTime(2016, 2, 29),
          DateTime(2021, 2, 27),
        ),
        4,
      );
      expect(
        MemoryLaneService.completedYearsBetween(
          DateTime(2016, 2, 29),
          DateTime(2021, 2, 28),
        ),
        5,
      );
    });

    test(
      "minimumEligibleCreationTimeMicros uses the same anniversary date",
      () {
        expect(
          DateTime.fromMicrosecondsSinceEpoch(
            MemoryLaneService.minimumEligibleCreationTimeMicros("2016-02-29")!,
          ),
          DateTime(2019, 2, 28),
        );
        expect(
          DateTime.fromMicrosecondsSinceEpoch(
            MemoryLaneService.minimumEligibleCreationTimeMicros("2010-10-15")!,
          ),
          DateTime(2013, 10, 15),
        );
      },
    );
  });
}
