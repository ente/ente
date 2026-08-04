import "dart:async";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/files_ml_indexed_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/service_locator.dart";
import "package:photos/utils/ml_util.dart";
import "package:photos/utils/network_util.dart";
import "package:synchronized/synchronized.dart";

/// Tracks ML indexing progress without polling: a baseline is computed once
/// from the DBs and afterwards updated in memory from [FilesMLIndexedEvent]s,
/// with a full recompute only when the library itself changes.
class MLIndexStatusService {
  final _logger = Logger("MLIndexStatusService");
  final _statusController = StreamController<IndexStatus>.broadcast();
  final _lock = Lock();

  MLIndexBaseline? _baseline;
  bool _dirty = true;
  bool _hasWifi = true;
  Timer? _refreshDebounce;
  Future<IndexStatus>? _inflightRefresh;

  MLIndexStatusService() {
    Bus.instance.on<FilesMLIndexedEvent>().listen(_onFilesIndexed);
    Bus.instance.on<LocalPhotosUpdatedEvent>().listen((_) => _markDirty());
    Connectivity().onConnectivityChanged.listen((_) {
      unawaited(_onConnectivityChanged());
    });
  }

  Stream<IndexStatus> get statusStream => _statusController.stream;

  Future<IndexStatus> getStatus({bool refresh = false}) {
    final baseline = _baseline;
    if (!refresh && !_dirty && baseline != null) {
      return Future.value(_statusFromBaseline(baseline));
    }
    return _refresh();
  }

  IndexStatus _statusFromBaseline(MLIndexBaseline baseline) {
    return IndexStatus(
      baseline.total - baseline.pendingFileKeys.length,
      baseline.pendingFileKeys.length,
      _hasWifi,
    );
  }

  Future<IndexStatus> _refresh() {
    return _inflightRefresh ??= _doRefresh().whenComplete(() {
      _inflightRefresh = null;
    });
  }

  Future<IndexStatus> _doRefresh() {
    return _lock.synchronized(() async {
      // Cleared before reading so invalidations that race the recompute are
      // not lost; restored on failure so stale data is not treated as fresh.
      _dirty = false;
      try {
        _hasWifi = await canUseHighBandwidth();
        final baseline = await computeMLIndexBaseline();
        _baseline = baseline;
        final status = _statusFromBaseline(baseline);
        _statusController.add(status);
        return status;
      } catch (e) {
        _dirty = true;
        rethrow;
      }
    });
  }

  Future<void> _onFilesIndexed(FilesMLIndexedEvent event) {
    // The lock ensures an in-flight baseline compute finishes before the
    // event is applied, so files indexed during the compute are not lost.
    return _lock.synchronized(() {
      final baseline = _baseline;
      if (baseline == null || _dirty) return;
      if (event.isLocalGallery != baseline.isLocalGallery) return;
      bool removedAny = false;
      bool unknownKey = false;
      for (final key in event.fileKeys) {
        if (baseline.pendingFileKeys.remove(key)) {
          removedAny = true;
        } else if (!baseline.allFileKeys.contains(key)) {
          unknownKey = true;
        }
      }
      if (unknownKey) {
        // A file outside the baseline's library snapshot got indexed (e.g.
        // newly uploaded or synced in), so the baseline is stale. Known but
        // non-pending keys are ignored: those were indexed while the baseline
        // itself was being computed.
        _logger.info("Baseline drift detected, scheduling recompute");
        _markDirty();
        return;
      }
      if (removedAny) {
        _statusController.add(_statusFromBaseline(baseline));
      }
    });
  }

  void _markDirty() {
    _dirty = true;
    if (!_statusController.hasListener || !hasGrantedMLConsent) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(seconds: 3), () {
      if (_dirty) _refresh().ignore();
    });
  }

  Future<void> _onConnectivityChanged() async {
    final hasWifi = await canUseHighBandwidth();
    if (hasWifi == _hasWifi) return;
    _hasWifi = hasWifi;
    final baseline = _baseline;
    if (baseline != null && !_dirty) {
      _statusController.add(_statusFromBaseline(baseline));
    }
  }
}
