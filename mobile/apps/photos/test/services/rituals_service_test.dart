import 'package:flutter_test/flutter_test.dart';
import 'package:photos/services/rituals/rituals_service.dart';

void main() {
  group('RitualsService.currentScheduledStreakFromDayKeys', () {
    test('keeps streak when today is enabled but incomplete', () {
      final todayMidnight = DateTime(2025, 6, 15);
      expect(_streak(todayMidnight, _offsets(1, 9)), 9);
    });

    test('increments streak after completing today', () {
      final todayMidnight = DateTime(2025, 6, 15);
      expect(_streak(todayMidnight, [0, ..._offsets(1, 9)]), 10);
    });

    test('resets streak when a previous enabled day was missed', () {
      final todayMidnight = DateTime(2025, 6, 15);
      expect(_streak(todayMidnight, _offsets(2, 10)), 0);
    });

    test('skips disabled days while keeping streak', () {
      final todayMidnight = DateTime(2025, 6, 16); // Monday
      final daysOfWeek = <bool>[
        false, // Sunday
        true, // Monday
        true, // Tuesday
        true, // Wednesday
        true, // Thursday
        true, // Friday
        false, // Saturday
      ];
      expect(_streak(todayMidnight, _offsets(3, 7), daysOfWeek), 5);
    });
  });
}

int _streak(DateTime today, List<int> completedOffsets, [List<bool>? days]) {
  final dayKeys = completedOffsets
      .map(
        (offset) => DateTime(
          today.year,
          today.month,
          today.day - offset,
        ).millisecondsSinceEpoch,
      )
      .toSet();
  return RitualsService.instance.currentScheduledStreakFromDayKeys(
    dayKeys,
    days ?? List<bool>.filled(7, true),
    todayMidnight: today,
  );
}

List<int> _offsets(int first, int last) => [
  for (var offset = first; offset <= last; offset++) offset,
];
