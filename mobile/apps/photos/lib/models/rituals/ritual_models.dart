import "package:flutter/material.dart";
import "package:photos/models/base/id.dart";
import "package:photos/models/file/file.dart";

class RitualsSummary {
  final Map<String, RitualProgress> ritualProgress;
  final DateTime generatedAt;

  const RitualsSummary({
    required this.ritualProgress,
    required this.generatedAt,
  });
}

class Ritual {
  Ritual({
    required this.id,
    required this.title,
    required this.daysOfWeek, // Sunday-first ordering of length 7
    required this.timeOfDay,
    required this.remindersEnabled,
    required this.albumId,
    required this.albumName,
    required this.icon,
    required this.createdAt,
  });

  final String id;
  final String title;
  final List<bool> daysOfWeek;
  final TimeOfDay timeOfDay;
  final bool remindersEnabled;
  final int? albumId;
  final String? albumName;
  final String icon;
  final DateTime createdAt;

  Ritual copyWith({
    String? id,
    String? title,
    List<bool>? daysOfWeek,
    TimeOfDay? timeOfDay,
    bool? remindersEnabled,
    int? albumId,
    String? albumName,
    String? icon,
    DateTime? createdAt,
  }) {
    return Ritual(
      id: id ?? this.id,
      title: title ?? this.title,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      albumId: albumId ?? this.albumId,
      albumName: albumName ?? this.albumName,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "title": title,
      "daysOfWeek": daysOfWeek,
      "hour": timeOfDay.hour,
      "minute": timeOfDay.minute,
      "remindersEnabled": remindersEnabled,
      "albumId": albumId,
      "albumName": albumName,
      "icon": icon,
      "createdAt": createdAt.millisecondsSinceEpoch,
    };
  }

  factory Ritual.fromJson(Map<String, dynamic> json) {
    final rawRemindersEnabled = json["remindersEnabled"];
    final remindersEnabled = rawRemindersEnabled is bool
        ? rawRemindersEnabled
        : rawRemindersEnabled is num
        ? rawRemindersEnabled != 0
        : true;
    return Ritual(
      id: json["id"] as String? ?? newID("ritual"),
      title: json["title"] as String? ?? "",
      daysOfWeek: List<bool>.from(
        (json["daysOfWeek"] as List<dynamic>? ?? List<bool>.filled(7, false)),
      ),
      timeOfDay: TimeOfDay(
        hour: (json["hour"] as num?)?.toInt() ?? 9,
        minute: (json["minute"] as num?)?.toInt() ?? 0,
      ),
      remindersEnabled: remindersEnabled,
      albumId: (json["albumId"] as num?)?.toInt(),
      albumName: json["albumName"] as String?,
      icon: json["icon"] as String? ?? "📸",
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json["createdAt"] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class RitualProgress {
  final String ritualId;
  final Set<int> completedDayKeys;
  final Map<int, EnteFile> recentFilesByDay;
  final Map<int, int> recentFileCountsByDay;
  final int currentStreak;
  final int longestStreakOverall;
  final int longestStreakThisMonth;

  const RitualProgress({
    required this.ritualId,
    required this.completedDayKeys,
    this.recentFilesByDay = const {},
    this.recentFileCountsByDay = const {},
    required this.currentStreak,
    required this.longestStreakOverall,
    required this.longestStreakThisMonth,
  });

  bool hasCompleted(DateTime day) {
    final key = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    return completedDayKeys.contains(key);
  }
}

class RitualsState {
  final bool loading;
  final RitualsSummary? summary;
  final List<Ritual> rituals;
  final String? error;

  const RitualsState({
    required this.loading,
    required this.summary,
    required this.rituals,
    required this.error,
  });

  factory RitualsState.loading() => const RitualsState(
    loading: true,
    summary: null,
    rituals: [],
    error: null,
  );

  RitualsState copyWith({
    bool? loading,
    RitualsSummary? summary,
    List<Ritual>? rituals,
    String? error,
  }) {
    return RitualsState(
      loading: loading ?? this.loading,
      summary: summary ?? this.summary,
      rituals: rituals ?? this.rituals,
      error: error,
    );
  }
}
