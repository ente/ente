import "dart:async";

import "package:logging/logging.dart";

class AlbumRefreshCoordinator {
  AlbumRefreshCoordinator(this._refresh);

  final Future<bool> Function(
    bool isFirstSync,
    void Function(String stage) setStage,
  )
  _refresh;
  final _logger = Logger("AlbumRefreshCoordinator");
  Future<bool>? _running;
  Completer<bool>? _pending;
  int _nextPassID = 0;

  Future<bool> request({bool isFirstSync = false}) {
    // First import must complete without joining ordinary refresh events.
    if (isFirstSync) return _runPass(isFirstSync: true);
    if (_running != null) {
      return (_pending ??= Completer<bool>()).future;
    }
    return _start(Completer<bool>());
  }

  Future<bool> _start(Completer<bool> completion) {
    _running = completion.future;
    unawaited(_completePass(completion));
    return completion.future;
  }

  Future<void> _completePass(Completer<bool> completion) async {
    try {
      completion.complete(await _runPass());
    } catch (error, stack) {
      completion.completeError(error, stack);
    } finally {
      final pending = _pending;
      _pending = null;
      _running = null;
      if (pending != null) unawaited(_start(pending));
    }
  }

  Future<bool> _runPass({bool isFirstSync = false}) async {
    final passID = ++_nextPassID;
    final stopwatch = Stopwatch()..start();
    var stage = "starting";
    _logger.info("Album refresh $passID started, firstSync=$isFirstSync");
    final warning = Timer(const Duration(minutes: 2), () {
      _logger.warning(
        "Album refresh $passID still running after ${stopwatch.elapsedMilliseconds}ms, "
        "stage=$stage, pending=${!isFirstSync && _pending != null}",
      );
    });
    try {
      final hasUpdated = await _refresh(isFirstSync, (value) => stage = value);
      _logger.info(
        "Album refresh $passID completed in ${stopwatch.elapsedMilliseconds}ms, "
        "updated=$hasUpdated",
      );
      return hasUpdated;
    } catch (error, stack) {
      _logger.severe(
        "Album refresh $passID failed after ${stopwatch.elapsedMilliseconds}ms, "
        "stage=$stage",
        error,
        stack,
      );
      rethrow;
    } finally {
      warning.cancel();
    }
  }
}
