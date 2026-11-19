import "dart:async";
import "dart:io";

import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:path/path.dart" as path;
import "package:path_provider/path_provider.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/ml/rust_db.dart";
import "package:photos/events/app_mode_changed_event.dart";
import "package:photos/events/diff_sync_complete_event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/main.dart" show isIOSBackgroundRefresh, isProcessBg;
import "package:photos/service_locator.dart";
import "package:photos/services/notification_service.dart";
import "package:photos/services/rewind/rewind_asset_store.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/services/rewind/rewind_progress.dart";
import "package:photos/services/rewind/rewind_request.dart";
import "package:photos/services/sync/local_sync_service.dart";
import "package:photos/services/sync/remote_sync_service.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/story/rewind_rituals.dart";
import "package:photos/ui/rewind/story/rewind_story.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:synchronized/synchronized.dart";

class RewindService {
  RewindService(SharedPreferences prefs) : _progress = RewindProgress(prefs) {
    Bus.instance.on<AppModeChangedEvent>().listen((_) => _reset());
    Bus.instance.on<PeopleChangedEvent>().listen((_) => _rebuildStory());
    Bus.instance.on<DiffSyncCompleteEvent>().listen((_) => _rebuildStory());
    Bus.instance
        .on<FilesUpdatedEvent>()
        .where((event) => _visibilityChanges.contains(event.type))
        .listen((_) => _rebuildStory());
    ritualsService.stateNotifier.addListener(_onRitualsChanged);
  }

  final RewindProgress _progress;
  final _logger = Logger("RewindService");
  final _lock = Lock();
  final _state = ValueNotifier<rust.RewindState?>(null);
  final _story = ValueNotifier<RewindStory?>(null);
  int? _storyComputedAt;
  String? _hiddenReason;
  String _missingStateReason = "no state";
  String? _storyError;
  final assets = RewindAssetStore();

  static const _startupDelay = Duration(seconds: 5);
  static const _refreshInterval = Duration(days: 1);
  static const _notificationId = 20261205;
  static const _notificationPayload = "ente://rewind";
  static const _notificationHour = 20;
  static const _notificationLeadTime = Duration(hours: 1);
  static const _visibilityChanges = {
    EventType.deletedFromDevice,
    EventType.deletedFromRemote,
    EventType.deletedFromEverywhere,
    EventType.archived,
    EventType.unarchived,
    EventType.hide,
    EventType.unhide,
  };

  ValueListenable<rust.RewindState?> get state => _state;

  ValueListenable<RewindStory?> get story => _story;

  RewindProgress get progress => _progress;

  late final Listenable changes = Listenable.merge([_story, _progress]);

  String get diagnosis {
    final hiddenReason = _hiddenReason;
    if (hiddenReason != null) return "hidden: $hiddenReason";
    return [
      _describe(_state.value),
      _storySummary,
      if (!memoriesCacheService.showAnyMemories)
        "home tile hidden because memories are off",
    ].join(", ");
  }

  void scheduleRefresh() {
    unawaited(_guarded(_showCached));
    unawaited(Future.delayed(_startupDelay, refresh));
  }

  Future<void> refresh({bool afterMlRun = false}) =>
      _guarded(() => _refresh(afterMlRun: afterMlRun));

  Future<void> _guarded(Future<void> Function() work) async {
    if (isIOSBackgroundRefresh) return;
    try {
      await _lock.synchronized(work);
    } catch (e, s) {
      _logger.warning("Failed to refresh Rewind", e, s);
    }
  }

  Future<void> recompute() => _lock.synchronized(() async {
    final owner = _owner;
    if (owner != null) {
      final cache = await _cacheFile(owner);
      if (await cache.exists()) await cache.delete();
    }
    await _refresh(afterMlRun: true);
  });

  Future<void> markOpened() async {
    await _progress.markOpened();
    await _lock.synchronized(
      () => NotificationService.instance.clearAllScheduledNotifications(
        containingPayload: _notificationPayload,
      ),
    );
  }

  Future<void> clear() async {
    _reset();
    final cache = Directory(await _cacheDirectory());
    if (await cache.exists()) await cache.delete(recursive: true);
  }

  void _reset() {
    _state.value = null;
    _missingStateReason = "no state";
    _setStory(null, null);
  }

  void _setStory(RewindStory? story, int? computedAt) {
    _story.value = story;
    _storyComputedAt = computedAt;
    _storyError = null;
  }

  Future<void> _showCached() async {
    final owner = _owner;
    if (owner == null) return;
    final stored = await _load(owner);
    if (stored == null || _madeWithDisabledMl(stored)) return;
    if (await _shownOwner(DateTime.now()) == owner) {
      await _publish(owner, stored, "cached");
    }
  }

  Future<void> _refresh({required bool afterMlRun}) async {
    final now = DateTime.now();
    final owner = await _shownOwner(now);
    if (owner == null) return;
    final stored = await _load(owner);
    await _publishCached(owner, stored);
    if (stored == null || !_isFresh(stored, now, afterMlRun: afterMlRun)) {
      await _publish(owner, await _compute(owner, stored, now), "computed");
    }
    await _updateNotification();
  }

  Future<int?> _shownOwner(DateTime now) async {
    final reason =
        _unavailableReason(now) ??
        (await assets.prepare() ? null : "assets are unavailable");
    final changed = reason != _hiddenReason;
    _hiddenReason = reason;
    if (reason == null) return _owner;
    if (changed) _logger.info("Rewind $diagnosis");
    _reset();
    return null;
  }

  String? _unavailableReason(DateTime now) {
    if (!RewindEdition.isAvailable(now)) {
      return "not available (flag ${flagService.rewind})";
    }
    if (_owner == null) return "no owner";
    if (!_hasSyncedLibrary) return "library has not synced yet";
    return null;
  }

  Future<void> _publishCached(int owner, rust.RewindState? stored) {
    final ignored = stored != null && _madeWithDisabledMl(stored);
    _missingStateReason = ignored
        ? "cached report was made with ML, which is now off"
        : "no cached report";
    return _publish(owner, ignored ? null : stored, "cached");
  }

  bool _madeWithDisabledMl(rust.RewindState state) =>
      state.mlCoverage != null && !rewindUsesMl;

  Future<void> _publish(
    int owner,
    rust.RewindState? state,
    String source,
  ) async {
    _state.value = owner == _owner ? state : null;
    await _buildStory();
    _logger.info("Rewind $source: $diagnosis");
  }

  String _describe(rust.RewindState? state) {
    if (state == null) return _missingStateReason;
    final status = switch (state.status) {
      rust.RewindStatus_Ready() => "ready",
      rust.RewindStatus_WaitingForMl() => "waiting for ML",
      rust.RewindStatus_NothingToShow() => "nothing to show",
    };
    final coverage = state.mlCoverage;
    final computedAt = DateTime.fromMicrosecondsSinceEpoch(state.computedAt);
    return [
      status,
      if (coverage != null)
        "ML coverage ${(coverage * 100).toStringAsFixed(1)}%",
      if (state.isFinal) "final",
      "computed at $computedAt",
    ].join(", ");
  }

  String get _storySummary {
    final story = _story.value;
    if (story != null) return "story of ${story.pages.length} pages";
    if (isProcessBg) return "no story in the background";
    final error = _storyError;
    return error == null ? "no story" : "story failed to build: $error";
  }

  Future<void> _rebuildStory({bool sharpenFaces = true}) async {
    if (_state.value?.status is! rust.RewindStatus_Ready) return;
    await _lock.synchronized(() {
      _storyComputedAt = null;
      return _buildStory(sharpenFaces: sharpenFaces);
    });
  }

  Future<void> revalidate() async {
    if (_story.value?.rituals == RewindRituals.current()) return;
    await _rebuildStory();
  }

  void _onRitualsChanged() {
    final story = _story.value;
    if (story == null || story.rituals == RewindRituals.current()) return;
    unawaited(_rebuildStory());
  }

  Future<void> _buildStory({bool sharpenFaces = true}) async {
    final state = _state.value;
    final status = state?.status;
    if (state == null || status is! rust.RewindStatus_Ready || isProcessBg) {
      _setStory(null, null);
      return;
    }
    if (state.computedAt == _storyComputedAt &&
        _story.value?.rituals == RewindRituals.current()) {
      return;
    }
    try {
      final timer = Stopwatch()..start();
      var story = await RewindStory.prepare(status.report);
      while (identical(_state.value, state) &&
          story.rituals != RewindRituals.current()) {
        story = await RewindStory.prepare(status.report);
      }
      if (!identical(_state.value, state)) return;
      _logger.info(
        "Built the Rewind story in ${timer.elapsedMilliseconds} ms, "
        "${story.blurryFaceFiles} files to sharpen faces from",
      );
      _setStory(story, state.computedAt);
      story.preloadFrom(
        story.resumeIndex(_progress.completed ? null : _progress.resumePage),
      );
      if (sharpenFaces) unawaited(_sharpenFaces(story));
    } catch (e, s) {
      _logger.warning("Failed to build the Rewind story", e, s);
      _setStory(null, null);
      _storyError = "$e";
    }
  }

  Future<void> _sharpenFaces(RewindStory story) async {
    if (!await story.sharpenFaces() || !identical(_story.value, story)) return;
    _logger.info("Sharpened Rewind faces, rebuilding the story");
    await _rebuildStory(sharpenFaces: false);
  }

  Future<rust.RewindState?> _compute(
    int owner,
    rust.RewindState? previous,
    DateTime now,
  ) async {
    final usesMl = rewindUsesMl;
    if (usesMl && !MLDataDB.isRustBackend) {
      _missingStateReason = "ML is on but the Rust ML DB is not";
      _logger.info("Skipping Rewind: $_missingStateReason");
      return previous?.mlCoverage != null ? previous : null;
    }
    final store = usesMl
        ? await (isLocalGalleryMode
                  ? RustMLDataDB.localGalleryInstance
                  : RustMLDataDB.instance)
              .store
        : null;
    final computed = await rust.computeRewind(
      request: await buildRewindRequest(now),
      store: store,
      cities: await locationService.getLocationIndex(),
      previous: previous,
    );
    final cache = await _cacheFile(owner);
    await cache.parent.create(recursive: true);
    await cache.writeAsBytes(await rust.encodeRewindState(state: computed));
    return computed;
  }

  int? get _owner =>
      isLocalGalleryMode ? 0 : Configuration.instance.getUserID();

  bool get _hasSyncedLibrary => isLocalGalleryMode
      ? LocalSyncService.instance.hasCompletedFirstImport()
      : RemoteSyncService.instance.isFirstRemoteSyncDone();

  Future<String> _cacheDirectory() async => path.join(
    (await getApplicationSupportDirectory()).path,
    "cache",
    "rewind",
  );

  Future<File> _cacheFile(int owner) async =>
      File(path.join(await _cacheDirectory(), "$owner.json"));

  Future<rust.RewindState?> _load(int owner) async {
    final cache = await _cacheFile(owner);
    if (!await cache.exists()) return null;
    return rust.decodeRewindState(
      bytes: await cache.readAsBytes(),
      year: RewindEdition.year,
      localGalleryMode: isLocalGalleryMode,
    );
  }

  bool _isFresh(
    rust.RewindState state,
    DateTime now, {
    required bool afterMlRun,
  }) {
    if (_madeWithDisabledMl(state)) return false;
    if (state.isFinal) return true;
    if ((state.mlCoverage != null) != rewindUsesMl) return false;
    if (afterMlRun && state.status is rust.RewindStatus_WaitingForMl) {
      return false;
    }
    return now.microsecondsSinceEpoch - state.computedAt <
        _refreshInterval.inMicroseconds;
  }

  Future<void> _updateNotification() async {
    final status = _state.value?.status;
    if (status is rust.RewindStatus_NothingToShow &&
        _progress.notificationScheduled) {
      await NotificationService.instance.clearAllScheduledNotifications(
        containingPayload: _notificationPayload,
      );
      await _progress.clearNotificationScheduled();
      return;
    }
    if (status is! rust.RewindStatus_Ready ||
        _progress.opened ||
        _progress.notificationScheduled ||
        !await NotificationService.instance.hasGrantedPermissions()) {
      return;
    }
    final scheduledAt = _notificationTime(DateTime.now());
    if (!scheduledAt.isBefore(RewindEdition.availableUntil)) return;
    final scheduled = await NotificationService.instance.scheduleNotification(
      "Your ${RewindEdition.year} Rewind is ready",
      message: "Your year in photos. Ready when you are.",
      id: _notificationId,
      channelID: "rewind",
      channelName: "Ente Rewind",
      payload: _notificationPayload,
      dateTime: scheduledAt,
    );
    if (scheduled) await _progress.markNotificationScheduled();
  }

  DateTime _notificationTime(DateTime now) {
    final today = DateTime(now.year, now.month, now.day, _notificationHour);
    return today.difference(now) >= _notificationLeadTime
        ? today
        : DateTime(now.year, now.month, now.day + 1, _notificationHour);
  }
}
