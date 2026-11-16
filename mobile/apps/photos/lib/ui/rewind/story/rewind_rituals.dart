import "dart:async";
import "dart:math";

import "package:collection/collection.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
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
    required this.started,
    required this.icons,
  });

  final int longestStreak;
  final int checkIns;
  final int busiestMonth;
  final int continued;
  final int built;
  final int started;
  final List<String> icons;

  static const _readyTimeout = Duration(seconds: 5);
  static final _logger = Logger("RewindRituals");

  static Future<RewindRituals?> settled() async {
    final state = ritualsService.stateNotifier.value;
    if (_pending(state)) {
      if (!state.loading) unawaited(ritualsService.refresh());
      if (!await _waitUntilSettled()) {
        _logger.warning("Rituals unavailable, Rewind continues without them");
      }
    }
    return current();
  }

  static bool _pending(RitualsState state) =>
      flagService.ritualsFlag &&
      state.summary == null &&
      state.error == null &&
      (state.loading || state.rituals.isNotEmpty);

  static Future<bool> _waitUntilSettled() async {
    final notifier = ritualsService.stateNotifier;
    final ready = Completer<bool>();
    void check() {
      if (ready.isCompleted || _pending(notifier.value)) return;
      ready.complete(notifier.value.summary != null);
    }

    notifier.addListener(check);
    check();
    try {
      return await ready.future.timeout(_readyTimeout, onTimeout: () => false);
    } finally {
      notifier.removeListener(check);
    }
  }

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
    final todayMidnight = DateTime(today.year, today.month, today.day);
    final end = todayMidnight.isBefore(lastDay) ? todayMidnight : lastDay;
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
      final currentStreak = ritualsService.currentScheduledStreakFromDayKeys(
        ritualProgress.completedDayKeys,
        ritual.daysOfWeek,
        todayMidnight: todayMidnight,
      );
      if (currentStreak > 0) continued++;
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
      started: checkInsByRitual.keys
          .where((ritual) => ritual.createdAt.year == year)
          .length,
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
      other.started == started &&
      listEquals(other.icons, icons);

  @override
  int get hashCode => Object.hash(
    longestStreak,
    checkIns,
    busiestMonth,
    continued,
    built,
    started,
    Object.hashAll(icons),
  );
}
