import "dart:math";

import "package:collection/collection.dart";
import "package:flutter/foundation.dart";
import "package:photos/models/rituals/ritual_models.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/ui/rituals/ritual_privacy.dart";

@immutable
class RewindRituals {
  const RewindRituals({
    required this.longestStreak,
    required this.checkIns,
    required this.busiestMonth,
    required this.continued,
    required this.built,
    required this.icons,
  });

  final int longestStreak;
  final int checkIns;
  final int busiestMonth;
  final int continued;
  final int built;
  final List<String> icons;

  static RewindRituals? current() {
    if (!flagService.ritualsFlag) return null;
    final state = ritualsService.stateNotifier.value;
    final summary = state.summary;
    if (summary == null) return null;
    return of(
      [
        for (final ritual in state.rituals)
          if (!isRitualAlbumHidden(ritual)) ritual,
      ],
      summary.ritualProgress,
      year: RewindEdition.year,
      today: DateTime.now(),
    );
  }

  static RewindRituals? of(
    List<Ritual> rituals,
    Map<String, RitualProgress> progress, {
    required int year,
    required DateTime today,
  }) {
    final firstDay = DateTime(year);
    final lastDay = DateTime(year, 12, 31);
    final end = today.isBefore(lastDay)
        ? DateTime(today.year, today.month, today.day)
        : lastDay;
    final months = List.filled(12, 0);
    final checkInsByRitual = <Ritual, int>{};
    var longest = 0;
    var continued = 0;
    for (final ritual in rituals) {
      final ritualProgress = progress[ritual.id];
      if (ritualProgress == null) continue;
      final days = {
        for (final key in ritualProgress.completedDayKeys)
          if (DateTime.fromMillisecondsSinceEpoch(key).year == year) key,
      };
      if (days.isEmpty) continue;
      for (final key in days) {
        months[DateTime.fromMillisecondsSinceEpoch(key).month - 1]++;
      }
      checkInsByRitual[ritual] = days.length;
      longest = max(
        longest,
        ritualsService.longestScheduledStreakInRange(
          days,
          ritual.daysOfWeek,
          startDay: firstDay,
          endDayInclusive: end,
        ),
      );
      if (ritualProgress.currentStreak > 0) continued++;
    }
    if (continued == 0 || longest == 0) return null;
    final busiest = months.indexed.reduce((a, b) => b.$2 > a.$2 ? b : a).$1;
    final ranked = checkInsByRitual.entries.sortedBy<num>(
      (entry) => -entry.value,
    );
    return RewindRituals(
      longestStreak: longest,
      checkIns: months.sum,
      busiestMonth: busiest + 1,
      continued: continued,
      built: checkInsByRitual.length,
      icons: {
        for (final entry in ranked)
          if (entry.key.icon.trim().isNotEmpty) entry.key.icon.trim(),
      }.toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RewindRituals &&
      other.longestStreak == longestStreak &&
      other.checkIns == checkIns &&
      other.busiestMonth == busiestMonth &&
      other.continued == continued &&
      other.built == built &&
      listEquals(other.icons, icons);

  @override
  int get hashCode => Object.hash(
    longestStreak,
    checkIns,
    busiestMonth,
    continued,
    built,
    Object.hashAll(icons),
  );
}
