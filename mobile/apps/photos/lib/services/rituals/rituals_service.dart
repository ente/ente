import "dart:async";
import "dart:convert";
import "dart:math";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/models/base/id.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/rituals/ritual_models.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/language_service.dart";
import "package:photos/services/notification_service.dart";
import "package:shared_preferences/shared_preferences.dart";

class RitualsService {
  static final RitualsService instance = RitualsService._privateConstructor();

  RitualsService._privateConstructor();

  static const _notificationLookaheadDays = 60;
  static const _maxScheduledNotificationsPerRitual = 30;
  final Logger _logger = Logger("RitualsService");
  final ValueNotifier<RitualsState> stateNotifier = ValueNotifier<RitualsState>(
    RitualsState.loading(),
  );
  late SharedPreferences _preferences;
  Timer? _debounce;
  int _refreshGeneration = 0;
  StreamSubscription<FilesUpdatedEvent>? _filesUpdatedSubscription;
  final Set<String> _notificationRescheduleInFlight = <String>{};

  static const _ritualsPrefsKey = "activity_rituals_v1";

  Future<void> init() async {
    _preferences = ServiceLocator.instance.prefs;
    if (!flagService.ritualsFlag) {
      stateNotifier.value = const RitualsState(
        loading: false,
        summary: null,
        rituals: [],
        error: null,
      );
      return;
    }
    _filesUpdatedSubscription = Bus.instance.on<FilesUpdatedEvent>().listen((
      event,
    ) {
      if (event is CollectionUpdatedEvent &&
          event.collectionID != null &&
          (event.type == EventType.deletedFromRemote ||
              event.type == EventType.deletedFromEverywhere)) {
        unawaited(_handleCollectionDeleted(event.collectionID!));
        return;
      }
      if (event is CollectionUpdatedEvent &&
          event.collectionID != null &&
          event.source == "rename_collection") {
        unawaited(_handleCollectionRenamed(event.collectionID!));
        return;
      }
      unawaited(_handleRitualNotificationsForUpdatedFiles(event));
      _scheduleRefresh();
    });
    _scheduleRefresh(initial: true, scheduleAllRituals: true);
    try {
      final rituals = await _loadRituals();
      stateNotifier.value = stateNotifier.value.copyWith(
        loading: false,
        rituals: rituals,
        error: null,
      );
    } catch (e, s) {
      _logger.severe("Failed to load rituals during init", e, s);
    }
  }

  void dispose() {
    _filesUpdatedSubscription?.cancel();
    _debounce?.cancel();
  }

  void _scheduleRefresh({
    bool initial = false,
    bool scheduleAllRituals = false,
  }) {
    _debounce?.cancel();
    _debounce = Timer(
      initial ? const Duration(seconds: 5) : const Duration(seconds: 1),
      () => unawaited(refresh(scheduleAllRituals: scheduleAllRituals)),
    );
  }

  Future<void> refresh({bool scheduleAllRituals = false}) async {
    if (!flagService.ritualsFlag) {
      stateNotifier.value = const RitualsState(
        loading: false,
        summary: null,
        rituals: [],
        error: null,
      );
      return;
    }
    final generation = ++_refreshGeneration;
    try {
      stateNotifier.value = stateNotifier.value.copyWith(
        loading: true,
        error: null,
      );
      final rituals = await _loadRituals();
      if (scheduleAllRituals) {
        _logger.info(
          "Scheduling ritual reminders for ${rituals.length} rituals (startup refresh)",
        );
        for (final ritual in rituals) {
          await _scheduleRitualNotifications(ritual);
        }
      }
      if (generation != _refreshGeneration) {
        return;
      }
      final summary = await _buildSummary(rituals);
      if (generation != _refreshGeneration) {
        return;
      }
      stateNotifier.value = RitualsState(
        loading: false,
        summary: summary,
        rituals: rituals,
        error: null,
      );
    } catch (e, s) {
      _logger.severe("Failed to refresh rituals", e, s);
      if (generation != _refreshGeneration) {
        return;
      }
      stateNotifier.value = stateNotifier.value.copyWith(
        loading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _handleCollectionDeleted(int collectionId) async {
    final state = stateNotifier.value;
    if (!state.loading &&
        !_shouldPruneRitualsForDeletedCollection(collectionId)) {
      return;
    }

    _debounce?.cancel();
    final generation = ++_refreshGeneration;
    final rituals = await _loadRituals();
    final summary = _filterSummaryForRituals(state.summary, rituals);
    if (generation != _refreshGeneration) {
      return;
    }
    stateNotifier.value = RitualsState(
      loading: false,
      summary: summary,
      rituals: rituals,
      error: null,
    );
  }

  bool _shouldPruneRitualsForDeletedCollection(int collectionId) {
    for (final ritual in stateNotifier.value.rituals) {
      final albumId = ritual.albumId;
      if (albumId == null || albumId <= 0) {
        return true;
      }
      if (albumId == collectionId) {
        return true;
      }
      final collection = collectionsService.getCollectionByID(albumId);
      if (collection == null || collection.isDeleted) {
        return true;
      }
    }
    return false;
  }

  Future<void> _handleCollectionRenamed(int collectionId) async {
    final state = stateNotifier.value;
    if (!state.loading &&
        !state.rituals.any((ritual) => ritual.albumId == collectionId)) {
      return;
    }

    _debounce?.cancel();
    final generation = ++_refreshGeneration;
    final rituals = await _loadRituals();
    final summary = _filterSummaryForRituals(state.summary, rituals);
    if (generation != _refreshGeneration) {
      return;
    }
    stateNotifier.value = RitualsState(
      loading: false,
      summary: summary,
      rituals: rituals,
      error: null,
    );
  }

  RitualsSummary? _filterSummaryForRituals(
    RitualsSummary? summary,
    List<Ritual> rituals,
  ) {
    if (summary == null) return null;
    if (summary.ritualProgress.isEmpty) return summary;

    final ritualIds = rituals.map((ritual) => ritual.id).toSet();
    if (ritualIds.isEmpty) {
      return RitualsSummary(
        ritualProgress: const {},
        generatedAt: summary.generatedAt,
      );
    }

    final filtered = <String, RitualProgress>{};
    for (final entry in summary.ritualProgress.entries) {
      if (ritualIds.contains(entry.key)) {
        filtered[entry.key] = entry.value;
      }
    }
    if (filtered.length == summary.ritualProgress.length) {
      return summary;
    }
    return RitualsSummary(
      ritualProgress: filtered,
      generatedAt: summary.generatedAt,
    );
  }

  Future<RitualsSummary> _buildSummary(List<Ritual> rituals) async {
    final userId = Configuration.instance.getUserID();
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);
    final monthEndInclusive = lastDayOfMonth.isAfter(todayMidnight)
        ? todayMidnight
        : lastDayOfMonth;
    if (userId == null) {
      return RitualsSummary(ritualProgress: {}, generatedAt: DateTime.now());
    }
    final ritualAlbumIds = rituals
        .map((r) => r.albumId)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();

    final Map<int, Set<int>> collectionDayKeys = {};
    final Map<int, Map<int, EnteFile>> collectionRecentFilesByDay = {};
    final Map<int, Map<int, int>> collectionRecentFileCountsByDay = {};

    if (ritualAlbumIds.isEmpty) {
      return RitualsSummary(
        ritualProgress: const {},
        generatedAt: DateTime.now(),
      );
    }

    final files = await FilesDB.instance.getAllFilesFromCollections(
      ritualAlbumIds,
    );
    final recentStart = todayMidnight.subtract(const Duration(days: 42));
    for (final EnteFile file in files) {
      final bool ownerMatches = file.ownerID == null
          ? true
          : file.ownerID == userId;
      final bool eligible =
          (file.uploadedFileID != null && file.uploadedFileID != -1) ||
          (file.localID != null && file.localID!.isNotEmpty);
      if (!(ownerMatches && eligible)) {
        continue;
      }
      if (file.creationTime == null) continue;
      final int? collectionId = file.collectionID;
      if (collectionId == null || collectionId <= 0) continue;
      if (!ritualAlbumIds.contains(collectionId)) continue;

      final date = DateTime.fromMicrosecondsSinceEpoch(
        file.creationTime!,
      ).toLocal();
      final bucket = DateTime(date.year, date.month, date.day);
      if (bucket.isAfter(todayMidnight)) continue;
      final dayKey = bucket.millisecondsSinceEpoch;
      collectionDayKeys.putIfAbsent(collectionId, () => <int>{}).add(dayKey);

      if (bucket.isBefore(recentStart)) continue;
      final countsByDay = collectionRecentFileCountsByDay.putIfAbsent(
        collectionId,
        () => <int, int>{},
      );
      countsByDay.update(dayKey, (value) => value + 1, ifAbsent: () => 1);
      final byDay = collectionRecentFilesByDay.putIfAbsent(
        collectionId,
        () => {},
      );
      final existing = byDay[dayKey];
      if (existing == null) {
        byDay[dayKey] = file;
        continue;
      }
      if ((existing.creationTime ?? -1) < (file.creationTime ?? -1)) {
        byDay[dayKey] = file;
      }
    }

    final ritualProgress = <String, RitualProgress>{};
    for (final ritual in rituals) {
      final albumId = ritual.albumId;
      if (albumId == null || albumId <= 0) continue;
      final dates = collectionDayKeys[albumId] ?? <int>{};
      final ritualLongestOverall = _longestScheduledStreakFromDayKeys(
        dates,
        ritual.daysOfWeek,
        todayMidnight: todayMidnight,
      );
      final ritualCurrent = currentScheduledStreakFromDayKeys(
        dates,
        ritual.daysOfWeek,
        todayMidnight: todayMidnight,
      );
      final ritualLongestThisMonth = _longestScheduledStreakInRangeFromDayKeys(
        dates,
        ritual.daysOfWeek,
        startDay: monthStart,
        endDayInclusive: monthEndInclusive,
      );

      ritualProgress[ritual.id] = RitualProgress(
        ritualId: ritual.id,
        completedDayKeys: dates,
        recentFilesByDay: collectionRecentFilesByDay[albumId] ?? const {},
        recentFileCountsByDay:
            collectionRecentFileCountsByDay[albumId] ?? const {},
        currentStreak: ritualCurrent,
        longestStreakOverall: ritualLongestOverall,
        longestStreakThisMonth: ritualLongestThisMonth,
      );
    }

    return RitualsSummary(
      ritualProgress: ritualProgress,
      generatedAt: DateTime.now(),
    );
  }

  Future<List<Ritual>> _loadRituals() async {
    final raw = _preferences.getStringList(_ritualsPrefsKey) ?? [];
    final rituals = raw
        .map((str) => Ritual.fromJson(Map<String, dynamic>.from(_decode(str))))
        .where((element) => element.id.isNotEmpty)
        .toList(growable: true);
    return _pruneOrphanedRituals(rituals);
  }

  Future<List<Ritual>> _pruneOrphanedRituals(List<Ritual> rituals) async {
    if (rituals.isEmpty) return rituals;

    final removed = <Ritual>[];
    final updated = <Ritual>[];
    bool namesUpdated = false;

    for (final ritual in rituals) {
      final albumId = ritual.albumId;
      if (albumId == null || albumId <= 0) {
        removed.add(ritual);
        continue;
      }
      final collection = collectionsService.getCollectionByID(albumId);
      if (collection == null || collection.isDeleted) {
        removed.add(ritual);
        continue;
      }

      final currentAlbumName = collection.displayName;
      if (ritual.albumName != currentAlbumName) {
        namesUpdated = true;
        updated.add(ritual.copyWith(albumName: currentAlbumName));
        continue;
      }

      updated.add(ritual);
    }

    if (removed.isEmpty && !namesUpdated) return rituals;

    if (removed.isNotEmpty) {
      _logger.info(
        "Pruning ${removed.length} orphaned rituals (missing/deleted album)",
      );
    }
    if (namesUpdated) {
      _logger.info("Updating ritual album names to match renamed albums");
    }

    await _persistRituals(updated);
    for (final ritual in removed) {
      await NotificationService.instance.clearAllScheduledNotifications(
        containingPayload: "ritualId=${ritual.id}",
        logLines: false,
      );
    }
    return updated;
  }

  Map<String, dynamic> _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _encode(Ritual ritual) => jsonEncode(ritual.toJson());

  Future<void> saveRitual(Ritual ritual) async {
    final rituals = await _loadRituals();
    final existingIndex = rituals.indexWhere((r) => r.id == ritual.id);
    final bool isNew = existingIndex == -1;
    final Ritual? previous = isNew ? null : rituals[existingIndex];
    final bool albumChanged = previous?.albumId != ritual.albumId;
    if (isNew) {
      rituals.add(ritual);
    } else {
      rituals[existingIndex] = ritual;
    }
    await _persistRituals(rituals);
    unawaited(_scheduleRitualNotifications(ritual));

    if (isNew || albumChanged) {
      await refresh();
    } else {
      // No ritual completion data changes; just update rituals in state.
      stateNotifier.value = stateNotifier.value.copyWith(
        rituals: rituals,
        loading: false,
        error: null,
      );
    }
  }

  Future<void> deleteRitual(String id) async {
    final rituals = await _loadRituals();
    rituals.removeWhere((r) => r.id == id);
    await _persistRituals(rituals);
    _logger.info("Clearing scheduled notifications for ritual $id (delete)");
    await NotificationService.instance.clearAllScheduledNotifications(
      containingPayload: "ritualId=$id",
      logLines: false,
    );
    await refresh();
  }

  Future<void> _persistRituals(List<Ritual> rituals) async {
    final encoded = rituals.map(_encode).toList();
    await _preferences.setStringList(_ritualsPrefsKey, encoded);
  }

  Future<void> _scheduleRitualNotifications(Ritual ritual) async {
    _logger.info(
      "Clearing scheduled notifications for ritual ${ritual.id} (save path)",
    );
    await NotificationService.instance.clearAllScheduledNotifications(
      containingPayload: ritual.id,
      logLines: false,
    );
    if (!ritual.remindersEnabled) {
      _logger.info(
        "Skipping scheduling ritual reminders for ritual ${ritual.id} (reminders disabled)",
      );
      return;
    }
    _logger.info(
      "Scheduling ritual reminders for ritual ${ritual.id} (save path)",
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayIndex = today.weekday % 7;
    final shouldCheckToday =
        ritual.daysOfWeek.length == 7 && ritual.daysOfWeek[todayIndex];
    final albumId = ritual.albumId;
    final skipToday = shouldCheckToday && albumId != null && albumId > 0
        ? await _hasAddedPhotoToday(albumId)
        : false;
    final baseId = ritual.id.hashCode & 0x7fffffff;
    final l10n = await LanguageService.locals;
    int scheduled = 0;
    for (
      int offset = 0;
      offset < _notificationLookaheadDays &&
          scheduled < _maxScheduledNotificationsPerRitual;
      offset++
    ) {
      final targetDate = today.add(Duration(days: offset));
      final dayIndex = targetDate.weekday % 7; // Sunday -> 0
      if (!ritual.daysOfWeek[dayIndex]) continue;
      if (offset == 0 && skipToday) {
        continue;
      }
      final icon = ritual.icon.isEmpty ? "📸" : ritual.icon;
      final title = ritual.title.trim().isEmpty
          ? icon
          : "$icon ${ritual.title.trim()}";
      final scheduledDate = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        ritual.timeOfDay.hour,
        ritual.timeOfDay.minute,
      );
      if (scheduledDate.isBefore(now)) {
        continue;
      }
      await NotificationService.instance.scheduleNotification(
        title,
        message: l10n.ritualNotificationMessage,
        id: baseId + scheduled,
        channelID: "ritual_reminders",
        channelName: l10n.ritualsTitle,
        payload: Uri(
          scheme: "ente",
          host: "camera",
          queryParameters: {
            "ritualId": ritual.id,
            "albumId": ritual.albumId?.toString() ?? "",
          },
        ).toString(),
        dateTime: scheduledDate,
        logSchedule: false,
      );
      scheduled += 1;
    }
  }

  Future<void> _handleRitualNotificationsForUpdatedFiles(
    FilesUpdatedEvent event,
  ) async {
    if (event.type != EventType.addedOrUpdated) return;
    final updatedCollectionIds = event.updatedFiles
        .map((file) => file.collectionID)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
    if (updatedCollectionIds.isEmpty) return;
    final rituals = stateNotifier.value.rituals;
    if (rituals.isEmpty) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayIndex = today.weekday % 7;

    for (final ritual in rituals) {
      final albumId = ritual.albumId;
      if (albumId == null || albumId <= 0) continue;
      if (!updatedCollectionIds.contains(albumId)) continue;
      if (!ritual.remindersEnabled) continue;
      if (ritual.daysOfWeek.length != 7 || !ritual.daysOfWeek[todayIndex]) {
        continue;
      }
      if (_notificationRescheduleInFlight.contains(ritual.id)) {
        continue;
      }
      _notificationRescheduleInFlight.add(ritual.id);
      try {
        final hasAddedToday = await _hasAddedPhotoToday(albumId);
        if (hasAddedToday) {
          await _scheduleRitualNotifications(ritual);
        }
      } finally {
        _notificationRescheduleInFlight.remove(ritual.id);
      }
    }
  }

  Future<bool> _hasAddedPhotoToday(int albumId) async {
    final userId = Configuration.instance.getUserID();
    if (userId == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final start = today.microsecondsSinceEpoch;
    final end = tomorrow.microsecondsSinceEpoch;
    try {
      final lowerBound = max(start - 1, 0);
      final files = await FilesDB.instance.getNewFilesInCollection(
        albumId,
        lowerBound,
      );
      for (final file in files) {
        final createdTime = file.creationTime;
        if (createdTime == null || createdTime < start || createdTime >= end) {
          continue;
        }
        final ownerMatches = file.ownerID == null
            ? true
            : file.ownerID == userId;
        if (!ownerMatches) continue;
        final eligible =
            (file.uploadedFileID != null && file.uploadedFileID != -1) ||
            (file.localID != null && file.localID!.isNotEmpty);
        if (!eligible) continue;
        return true;
      }
    } catch (e, s) {
      _logger.warning(
        "Failed to check ritual album additions for $albumId",
        e,
        s,
      );
    }
    return false;
  }

  @visibleForTesting
  int currentScheduledStreakFromDayKeys(
    Set<int> dayKeys,
    List<bool> daysOfWeek, {
    required DateTime todayMidnight,
  }) {
    if (dayKeys.isEmpty) return 0;
    if (daysOfWeek.length != 7) return 0;

    final start = _streakStartDateFromDayKeys(dayKeys, todayMidnight);
    int current = 0;
    for (var day = todayMidnight; !day.isBefore(start); day = _prevDay(day)) {
      final dayIndex = day.weekday % 7; // Sunday -> 0
      if (!_isScheduledDay(daysOfWeek, dayIndex)) continue;

      final key = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
      if (dayKeys.contains(key)) {
        current += 1;
        continue;
      }
      if (day == todayMidnight) {
        continue;
      }
      break;
    }
    return current;
  }

  int _longestScheduledStreakFromDayKeys(
    Set<int> dayKeys,
    List<bool> daysOfWeek, {
    required DateTime todayMidnight,
  }) {
    if (dayKeys.isEmpty) return 0;
    if (daysOfWeek.length != 7) return 0;

    final start = _streakStartDateFromDayKeys(dayKeys, todayMidnight);
    int longest = 0;
    int rolling = 0;
    for (var day = start; !day.isAfter(todayMidnight); day = _nextDay(day)) {
      final dayIndex = day.weekday % 7; // Sunday -> 0
      if (!_isScheduledDay(daysOfWeek, dayIndex)) continue;

      final key = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
      if (dayKeys.contains(key)) {
        rolling += 1;
        longest = max(longest, rolling);
      } else {
        rolling = 0;
      }
    }
    return longest;
  }

  int _longestScheduledStreakInRangeFromDayKeys(
    Set<int> dayKeys,
    List<bool> daysOfWeek, {
    required DateTime startDay,
    required DateTime endDayInclusive,
  }) {
    if (dayKeys.isEmpty) return 0;
    if (daysOfWeek.length != 7) return 0;
    if (endDayInclusive.isBefore(startDay)) return 0;

    int longest = 0;
    int rolling = 0;
    for (
      var day = startDay;
      !day.isAfter(endDayInclusive);
      day = _nextDay(day)
    ) {
      final dayIndex = day.weekday % 7; // Sunday -> 0
      if (!_isScheduledDay(daysOfWeek, dayIndex)) continue;

      final key = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
      if (dayKeys.contains(key)) {
        rolling += 1;
        longest = max(longest, rolling);
      } else {
        rolling = 0;
      }
    }
    return longest;
  }

  DateTime _streakStartDateFromDayKeys(
    Set<int> dayKeys,
    DateTime todayMidnight,
  ) {
    final minKey = dayKeys.reduce(min);
    final minDay = DateTime.fromMillisecondsSinceEpoch(minKey);
    final start = DateTime(minDay.year, minDay.month, minDay.day);
    return start.isAfter(todayMidnight) ? todayMidnight : start;
  }

  bool _hasAnyEnabledRitualDays(List<bool> daysOfWeek) {
    if (daysOfWeek.length != 7) return false;
    for (final enabled in daysOfWeek) {
      if (enabled) return true;
    }
    return false;
  }

  bool _isScheduledDay(List<bool> daysOfWeek, int dayIndex) {
    if (daysOfWeek.length != 7) return false;
    if (!_hasAnyEnabledRitualDays(daysOfWeek)) return true;
    return daysOfWeek[dayIndex];
  }

  DateTime _nextDay(DateTime day) => DateTime(day.year, day.month, day.day + 1);

  DateTime _prevDay(DateTime day) => DateTime(day.year, day.month, day.day - 1);

  Ritual createEmptyRitual() {
    return Ritual(
      id: newID("ritual"),
      title: "",
      daysOfWeek: List<bool>.filled(7, true),
      timeOfDay: const TimeOfDay(hour: 9, minute: 0),
      remindersEnabled: true,
      albumId: null,
      albumName: null,
      icon: "📸",
      createdAt: DateTime.now(),
    );
  }
}
