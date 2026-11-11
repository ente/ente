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
        .where((event) => _fileRemovals.contains(event.type))
        .listen((_) => _rebuildStory());
  }

  final RewindProgress _progress;
  final _logger = Logger("RewindService");
  final _lock = Lock();
  final _state = ValueNotifier<rust.RewindState?>(null);
  final _story = ValueNotifier<RewindStory?>(null);
  int? _storyComputedAt;
  final assets = RewindAssetStore();

  static const _startupDelay = Duration(seconds: 5);
  static const _refreshInterval = Duration(days: 1);
  static const _notificationId = 20261205;
  static const _notificationPayload = "ente://rewind";
  static const _notificationHour = 20;
  static const _notificationLeadTime = Duration(hours: 1);
  static const _fileRemovals = {
    EventType.deletedFromDevice,
    EventType.deletedFromRemote,
    EventType.deletedFromEverywhere,
    EventType.archived,
    EventType.hide,
  };

  ValueListenable<rust.RewindState?> get state => _state;

  ValueListenable<RewindStory?> get story => _story;

  RewindProgress get progress => _progress;

  late final Listenable changes = Listenable.merge([_story, _progress]);

  void scheduleRefresh() => unawaited(Future.delayed(_startupDelay, refresh));

  Future<void> refresh({bool afterMlRun = false}) async {
    if (isIOSBackgroundRefresh) return;
    try {
      await _lock.synchronized(() => _refresh(afterMlRun: afterMlRun));
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
    _setStory(null, null);
  }

  void _setStory(RewindStory? story, int? computedAt) {
    _story.value = story;
    _storyComputedAt = computedAt;
  }

  Future<void> _refresh({required bool afterMlRun}) async {
    final now = DateTime.now();
    if (!RewindEdition.isAvailable(now)) {
      _reset();
      return;
    }
    final owner = _owner;
    if (owner == null || !_hasSyncedLibrary || !await assets.prepare()) {
      _reset();
      return;
    }
    final stored = await _load(owner);
    await _publish(owner, stored);
    if (stored == null || !_isFresh(stored, now, afterMlRun: afterMlRun)) {
      await _publish(owner, await _compute(owner, stored, now));
    }
    await _updateNotification();
  }

  Future<void> _publish(int owner, rust.RewindState? state) async {
    _state.value = owner == _owner ? state : null;
    await _buildStory();
  }

  Future<void> _rebuildStory() async {
    if (_state.value?.status is! rust.RewindStatus_Ready) return;
    await _lock.synchronized(() {
      _storyComputedAt = null;
      return _buildStory();
    });
  }

  Future<void> _buildStory() async {
    final state = _state.value;
    final status = state?.status;
    if (state == null || status is! rust.RewindStatus_Ready || isProcessBg) {
      _setStory(null, null);
      return;
    }
    if (state.computedAt == _storyComputedAt) return;
    try {
      final story = await RewindStory.prepare(status.report);
      if (!identical(_state.value, state)) return;
      _setStory(story, state.computedAt);
      story.preloadFrom(
        story.resumeIndex(_progress.completed ? null : _progress.resumePage),
      );
    } catch (e, s) {
      _logger.warning("Failed to build the Rewind story", e, s);
    }
  }

  Future<rust.RewindState?> _compute(
    int owner,
    rust.RewindState? previous,
    DateTime now,
  ) async {
    final usesMl = rewindUsesMl;
    if (usesMl && !MLDataDB.isRustBackend) {
      _logger.info("Skipping Rewind: ML is on but the Rust ML DB is not");
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
    if (state.mlCoverage != null && !rewindUsesMl) return false;
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
