import "dart:async";
import "dart:io";

import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:path/path.dart" as path;
import "package:path_provider/path_provider.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/rust_db.dart";
import "package:photos/events/app_mode_changed_event.dart";
import "package:photos/events/diff_sync_complete_event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/events/sync_finished_event.dart";
import "package:photos/events/sync_status_update_event.dart";
import "package:photos/main.dart" show isIOSBackgroundRefresh, isProcessBg;
import "package:photos/service_locator.dart";
import "package:photos/services/app_lifecycle_service.dart";
import "package:photos/services/memories/memory_music_service.dart";
import "package:photos/services/notification_service.dart";
import "package:photos/services/rewind/rewind_asset_store.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/services/rewind/rewind_progress.dart";
import "package:photos/services/rewind/rewind_request.dart";
import "package:photos/services/sync/local_sync_service.dart";
import "package:photos/services/sync/offline_import_metadata_service.dart";
import "package:photos/services/sync/remote_sync_service.dart";
import "package:photos/src/rust/api/ml_db_api.dart" show MlStore;
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/copy/rewind_copy.dart";
import "package:photos/ui/rewind/story/rewind_rituals.dart";
import "package:photos/ui/rewind/story/rewind_story.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:synchronized/synchronized.dart";

class RewindService {
  RewindService(this._prefs) : _progress = RewindProgress(_prefs) {
    Bus.instance.on<AppModeChangedEvent>().listen((_) => _reset());
    Bus.instance.on<PeopleChangedEvent>().listen((_) => _rebuildStory());
    Bus.instance.on<DiffSyncCompleteEvent>().listen((_) => _rebuildStory());
    Bus.instance.on<SyncFinishedEvent>().listen((_) => _refreshIfOutdated());
    Bus.instance
        .on<SyncStatusUpdate>()
        .where((event) => event.status == SyncStatus.completedBackup)
        .listen((_) => _refreshIfOutdated());
    Bus.instance
        .on<LocalPhotosUpdatedEvent>()
        .where((event) => event.source == _localMetadataSource)
        .listen((_) => _refreshOnceLocalMetadataSettles());
    Bus.instance
        .on<FilesUpdatedEvent>()
        .where((event) => _visibilityChanges.contains(event.type))
        .listen((_) => _rebuildStory());
    ritualsService.stateNotifier.addListener(_onRitualsChanged);
  }

  final SharedPreferences _prefs;
  final RewindProgress _progress;
  final _logger = Logger("RewindService");
  final _lock = Lock();
  final _state = ValueNotifier<rust.RewindState?>(null);
  final _story = ValueNotifier<RewindStory?>(null);
  final _revealed = ValueNotifier<bool>(false);
  int? _storyComputedAt;
  String? _hiddenReason;
  String _missingStateReason = "no state";
  String? _storyError;
  var _hasRefreshed = false;
  Timer? _localMetadataTimer;
  final assets = RewindAssetStore();
  late final music = MemoryMusicService.remote(
    manifestURL: "https://rewind-assets.ente.com/rewind-2026-music.json",
    manifestPreferenceKey: "rewind_2026_music_manifest",
  );

  static const _startupDelay = Duration(seconds: 5);
  static const _startupRetryDelay = Duration(seconds: 30);
  static const _refreshInterval = Duration(days: 1);
  static const _toleratedShare = 0.1;
  static const _mostChangesBeforeRecompute = 50;
  static const _uploadLookback = Duration(minutes: 5);
  static const _longestOfflineMetadataWait = Duration(days: 1);
  static const _libraryCountKey =
      "ls.rewind_${RewindEdition.year}_library_count";
  static const _offlineMetadataWaitKey =
      "ls.rewind_${RewindEdition.year}_offline_metadata_wait";
  static const _localMetadataSource = "offlineImportMetadata";
  static const _localMetadataQuietPeriod = Duration(seconds: 30);
  static const _notificationId = 20261205;
  static const _newCardsNotificationId = 20261206;
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

  bool get revealed => _revealed.value;

  RewindProgress get progress => _progress;

  bool get hasPendingMlChapters => switch (_state.value) {
    final state? =>
      state.status is rust.RewindStatus_Ready &&
          !state.isFinal &&
          (state.mlChaptersPending ||
              (state.mlCoverage == null && rewindUsesMl)),
    null => false,
  };

  late final Listenable changes = Listenable.merge([
    _story,
    _revealed,
    _progress,
  ]);

  String get diagnosis {
    final hiddenReason = _hiddenReason;
    if (hiddenReason != null) return "hidden: $hiddenReason";
    return [
      _describe(_state.value),
      _storySummary,
      if (!memoriesCacheService.showAnyMemories)
        "home tile hidden because memories are off",
      if (RewindEdition.isPrelaunch(DateTime.now()))
        "hidden until ${RewindEdition.availableFrom}",
    ].join(", ");
  }

  void scheduleRefresh() {
    unawaited(_guarded(_showCached));
    unawaited(_refreshAtStartup());
  }

  Future<void> _refreshAtStartup() async {
    await Future.delayed(_startupDelay, refresh);
    await Future.delayed(_startupRetryDelay, _refreshIfOutdated);
  }

  Future<void> refresh({bool afterMlRun = false, bool justClustered = false}) =>
      _guarded(
        () => _refresh(afterMlRun: afterMlRun, justClustered: justClustered),
      );

  Future<void> _refreshIfOutdated() async {
    if (isProcessBg || !_hasRefreshed) return;
    await _guarded(() async {
      final state = _state.value;
      if (state != null && !await _libraryChanged(state)) return;
      await _refresh(afterMlRun: false);
    });
  }

  void _refreshOnceLocalMetadataSettles() {
    _localMetadataTimer?.cancel();
    _localMetadataTimer = Timer(
      _localMetadataQuietPeriod,
      () => unawaited(_refreshIfOutdated()),
    );
  }

  Future<bool> _libraryChanged(rust.RewindState state) async {
    if (state.isFinal) return false;
    final changed =
        await _libraryCount(state.computedAt) - _libraryCountWhen(state);
    return changed >= _changesForRecompute(state);
  }

  Future<int> _libraryCount(int computedAt) async {
    if (!isLocalGalleryMode) {
      return _ownedFilesUpdatedSince(
        computedAt - _uploadLookback.inMicroseconds,
      );
    }
    return _tracksOfflineMetadata ? _processedOfflineFiles() : 0;
  }

  int _libraryCountWhen(rust.RewindState state) {
    final saved = _prefs.getStringList(_libraryCountKey);
    if (saved == null || saved.first != "${state.computedAt}") return 0;
    return int.tryParse(saved.last) ?? 0;
  }

  bool get _tracksOfflineMetadata => isLocalGalleryMode && Platform.isAndroid;

  int _changesForRecompute(rust.RewindState state) {
    final files = switch (state.status) {
      rust.RewindStatus_Ready(:final report) => report.totals?.files ?? 0,
      rust.RewindStatus_NothingToShow() => 0,
    };
    return (files * _toleratedShare).ceil().clamp(
      1,
      _mostChangesBeforeRecompute,
    );
  }

  Future<bool> _waitsForOfflineMetadata(DateTime now) async {
    if (!_tracksOfflineMetadata || _progress.opened) return false;
    final waitingSince = _prefs.getInt(_offlineMetadataWaitKey);
    if (waitingSince != null &&
        now.microsecondsSinceEpoch - waitingSince >=
            _longestOfflineMetadataWait.inMicroseconds) {
      return false;
    }
    final (:total, :unread) = await FilesDB.instance
        .countOfflineFilesCapturedBetween(
          OfflineImportMetadataService.kProcessingVersion,
          capturedFrom: _yearCaptureStart,
          capturedBefore: _yearCaptureCutoff,
        );
    if (unread <= total * _toleratedShare) return false;
    if (waitingSince == null) {
      await _prefs.setInt(_offlineMetadataWaitKey, now.microsecondsSinceEpoch);
    }
    return true;
  }

  Future<int> _ownedFilesUpdatedSince(int time) async {
    final userID = Configuration.instance.getUserID();
    if (userID == null) return 0;
    return FilesDB.instance.countOwnedFilesUpdatedSince(
      userID,
      time,
      capturedBefore: _yearCaptureCutoff,
    );
  }

  Future<int> _processedOfflineFiles() =>
      FilesDB.instance.countProcessedOfflineFiles(
        OfflineImportMetadataService.kProcessingVersion,
        capturedBefore: _yearCaptureCutoff,
      );

  int get _yearCaptureStart =>
      DateTime.utc(RewindEdition.year - 1, 12, 31).microsecondsSinceEpoch;

  int get _yearCaptureCutoff =>
      DateTime.utc(RewindEdition.year + 1, 1, 2).microsecondsSinceEpoch;

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

  Future<bool> hasEnoughMl() async {
    if (!rewindUsesMl) return false;
    try {
      return await rust.rewindHasEnoughMl(
        year: RewindEdition.year,
        files: await buildRewindCoverageFiles(),
        store: await _mlStore,
      );
    } catch (e, s) {
      _logger.warning("Failed to check Rewind's ML coverage", e, s);
      return false;
    }
  }

  Future<void> markOpened() async {
    await _progress.markOpened();
    await _clearScheduledNotifications();
  }

  Future<void> dismiss() async {
    await _progress.markDismissed();
    if (_progress.opened) await _clearScheduledNotifications();
  }

  Future<void> _clearScheduledNotifications() => _lock.synchronized(
    () => NotificationService.instance.clearAllScheduledNotifications(
      containingPayload: _notificationPayload,
    ),
  );

  Future<void> clear() async {
    _reset();
    final cache = Directory(await _cacheDirectory());
    if (await cache.exists()) await cache.delete(recursive: true);
  }

  void _reset() {
    _state.value = null;
    _hiddenReason = null;
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

  Future<void> _refresh({
    required bool afterMlRun,
    bool justClustered = false,
  }) async {
    _hasRefreshed = true;
    final now = DateTime.now();
    final owner = await _shownOwner(now);
    if (owner == null) return;
    final stored = await _load(owner);
    await _publishCached(owner, stored);
    if (stored == null && await _waitsForOfflineMetadata(now)) {
      _missingStateReason = "waiting for this year's photo details";
      _logger.info("Rewind $diagnosis");
      return;
    }
    if (stored == null ||
        !_isFresh(stored, now) ||
        await _libraryChanged(stored) ||
        (afterMlRun && stored.mlChaptersPending && await hasEnoughMl())) {
      final libraryCount = await _libraryCount(now.microsecondsSinceEpoch);
      final computed = await _compute(
        owner,
        stored,
        await buildRewindRequest(now, justClustered: justClustered),
      );
      await _prefs.setStringList(_libraryCountKey, [
        "${computed.computedAt}",
        "$libraryCount",
      ]);
      await _publish(owner, computed, "computed");
      await _notifyNewCards(stored, computed);
    }
    await _updateNotification();
  }

  Future<int?> _shownOwner(DateTime now) async {
    final reason =
        _unavailableReason(now) ??
        (await assets.prepare() ? null : "assets are unavailable");
    final changed = reason != _hiddenReason;
    if (reason == null) {
      _hiddenReason = null;
      return _owner;
    }
    _reset();
    _hiddenReason = reason;
    if (changed) _logger.info("Rewind $diagnosis");
    return null;
  }

  String? _unavailableReason(DateTime now) {
    if (!RewindEdition.canPrepare(now)) {
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

  bool _madeBeforeLaunch(rust.RewindState state) =>
      RewindEdition.isAvailable(DateTime.now()) &&
      RewindEdition.isPrelaunch(
        DateTime.fromMicrosecondsSinceEpoch(state.computedAt),
      );

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
      rust.RewindStatus_NothingToShow() => "nothing to show",
    };
    final coverage = state.mlCoverage;
    final computedAt = DateTime.fromMicrosecondsSinceEpoch(state.computedAt);
    return [
      status,
      if (coverage != null)
        "ML coverage ${(coverage * 100).toStringAsFixed(1)}%",
      if (state.mlChaptersPending) "ML cards pending",
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
    _revealed.value = RewindEdition.isAvailable(DateTime.now());
    final state = _state.value;
    final status = state?.status;
    if (state == null ||
        status is! rust.RewindStatus_Ready ||
        isProcessBg ||
        _madeBeforeLaunch(state)) {
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
      final resumeIndex = story.resumeIndex(
        _progress.completed ? null : _progress.resumePage,
      );
      story.preloadFrom(resumeIndex);
      if (AppLifecycleService.instance.isForeground) {
        unawaited(_cachePhotos(story, resumeIndex));
        unawaited(music.prepare());
      }
      if (sharpenFaces) unawaited(_sharpenFaces(story));
    } catch (e, s) {
      _logger.warning("Failed to build the Rewind story", e, s);
      _setStory(null, null);
      _storyError = "$e";
    }
  }

  Future<void> _cachePhotos(RewindStory story, int from) async {
    final timer = Stopwatch()..start();
    bool isCurrent() => identical(_story.value, story);
    final (:cached, :total) = await story.cachePhotos(from, isCurrent);
    if (!isCurrent()) return;
    _logger.info(
      "Cached $cached of $total Rewind photos in "
      "${timer.elapsedMilliseconds} ms",
    );
  }

  Future<void> _sharpenFaces(RewindStory story) async {
    if (!await story.sharpenFaces() || !identical(_story.value, story)) return;
    _logger.info("Sharpened Rewind faces, rebuilding the story");
    await _rebuildStory(sharpenFaces: false);
  }

  Future<rust.RewindState> _compute(
    int owner,
    rust.RewindState? previous,
    rust.RewindRequest request,
  ) async {
    final computed = await rust.computeRewind(
      request: request,
      store: rewindUsesMl ? await _mlStore : null,
      cities: await locationService.getLocationIndex(),
      previous: previous,
    );
    final bytes = await rust.encodeRewindState(state: computed);
    final cache = await _cacheFile(owner);
    await cache.parent.create(recursive: true);
    if (owner == _owner) await cache.writeAsBytes(bytes);
    return computed;
  }

  Future<MlStore> get _mlStore =>
      (isLocalGalleryMode
              ? RustMLDataDB.localGalleryInstance
              : RustMLDataDB.instance)
          .store;

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
    final stored = await rust.decodeRewindState(
      bytes: await cache.readAsBytes(),
      year: RewindEdition.year,
      localGalleryMode: isLocalGalleryMode,
    );
    return stored == null || _madeBeforeLaunch(stored) ? null : stored;
  }

  bool _isFresh(rust.RewindState state, DateTime now) {
    if (_madeWithDisabledMl(state)) return false;
    if (state.isFinal) return true;
    if ((state.mlCoverage != null) != rewindUsesMl) return false;
    return now.microsecondsSinceEpoch - state.computedAt <
        _refreshInterval.inMicroseconds;
  }

  Future<void> _updateNotification() async {
    final state = _state.value;
    final status = state?.status;
    if (status is rust.RewindStatus_NothingToShow &&
        _progress.notificationScheduled) {
      await NotificationService.instance.clearAllScheduledNotifications(
        containingPayload: _notificationPayload,
      );
      await _progress.clearNotificationScheduled();
      return;
    }
    if (state == null ||
        status is! rust.RewindStatus_Ready ||
        !_revealed.value ||
        _madeBeforeLaunch(state) ||
        _progress.opened ||
        _progress.notificationScheduled ||
        !await NotificationService.instance.hasGrantedPermissions()) {
      return;
    }
    final copy = await RewindCopy.current();
    if (await _scheduleNotification(
      _notificationId,
      copy.readyTitle,
      copy.readyBody,
      _notificationTime(DateTime.now()),
    )) {
      await _progress.markNotificationScheduled();
    }
  }

  Future<void> _notifyNewCards(
    rust.RewindState? before,
    rust.RewindState after,
  ) async {
    if (!_revealed.value ||
        before?.status is! rust.RewindStatus_Ready ||
        _showsMlCards(before) ||
        !_showsMlCards(after)) {
      return;
    }
    if (isProcessBg) await _progress.reload();
    if (!_progress.opened ||
        _progress.dismissed ||
        _progress.newCardsNotified ||
        !await NotificationService.instance.hasGrantedPermissions()) {
      return;
    }
    final now = DateTime.now();
    final slot = _notificationTime(now);
    final copy = await RewindCopy.current();
    if (await _scheduleNotification(
      _newCardsNotificationId,
      copy.newCardsTitle,
      copy.newCardsBody,
      slot.isBefore(RewindEdition.availableUntil)
          ? slot
          : now.add(_notificationLeadTime),
    )) {
      await _progress.markNewCardsNotified();
    }
  }

  Future<bool> _scheduleNotification(
    int id,
    String title,
    String message,
    DateTime scheduledAt,
  ) {
    if (!scheduledAt.isBefore(RewindEdition.availableUntil)) {
      return Future.value(false);
    }
    return NotificationService.instance.scheduleNotification(
      title,
      message: message,
      id: id,
      channelID: "rewind",
      channelName: "Ente Rewind",
      payload: _notificationPayload,
      dateTime: scheduledAt,
    );
  }

  bool _showsMlCards(rust.RewindState? state) => switch (state?.status) {
    rust.RewindStatus_Ready(:final report) =>
      report.colour != null ||
          report.peopleRace != null ||
          report.newFaces != null,
    _ => false,
  };

  DateTime _notificationTime(DateTime now) {
    final today = DateTime(now.year, now.month, now.day, _notificationHour);
    return today.difference(now) >= _notificationLeadTime
        ? today
        : DateTime(now.year, now.month, now.day + 1, _notificationHour);
  }
}
