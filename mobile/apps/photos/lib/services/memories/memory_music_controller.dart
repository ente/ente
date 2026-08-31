import "dart:async";

import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/models/memories/memory_music_track.dart";
import "package:photos/services/memories/memory_music_player.dart";

enum _MemoryMusicPlaybackStatus { idle, loading, ready }

enum _MemoryMusicPauseReason { appBackground, viewerAction, videoItem }

class MemoryMusicController extends ChangeNotifier {
  final Map<String, MemoryMusicTrack> _assignments;
  final List<MemoryMusicTrack> _tracks;
  final MemoryMusicPlayer _player;
  final Future<void> Function(bool isMuted) _persistMuted;
  final Logger _logger = Logger("MemoryMusicController");
  final Set<_MemoryMusicPauseReason> _pauseReasons =
      <_MemoryMusicPauseReason>{};
  final Set<String> _unavailableTrackIDs = <String>{};

  Future<void>? _audioSessionInitialization;

  _MemoryMusicPlaybackStatus _status = _MemoryMusicPlaybackStatus.idle;
  String? _activeMemoryID;
  bool _isMuted;
  bool _isDisposed = false;
  int _loadGeneration = 0;

  MemoryMusicController({
    required Map<String, MemoryMusicTrack> assignments,
    required bool initiallyMuted,
    required Future<void> Function(bool isMuted) persistMuted,
    required MemoryMusicPlayer player,
    required List<MemoryMusicTrack> tracks,
  }) : _assignments = assignments,
       _tracks = tracks,
       _isMuted = initiallyMuted,
       _persistMuted = persistMuted,
       _player = player;

  bool get isMuted => _isMuted;

  Future<void> activateMemory(
    String memoryID, {
    required bool currentItemIsVideo,
  }) async {
    if (_isDisposed) return;

    final sameMemory = _activeMemoryID == memoryID;
    _activeMemoryID = memoryID;
    final itemPauseChanged = _setPauseReason(
      _MemoryMusicPauseReason.videoItem,
      currentItemIsVideo,
    );
    if (sameMemory &&
        (_status == _MemoryMusicPlaybackStatus.ready ||
            _status == _MemoryMusicPlaybackStatus.loading)) {
      if (itemPauseChanged) await _synchronizePlayback();
      return;
    }

    final assignedTrack = _assignments[memoryID]!;
    final generation = ++_loadGeneration;
    _status = _MemoryMusicPlaybackStatus.loading;
    await _synchronizePlayback();
    if (!_isCurrentLoad(generation)) return;

    final candidates = <MemoryMusicTrack>[
      assignedTrack,
      for (final track in _tracks)
        if (track.id != assignedTrack.id) track,
    ];
    for (final track in candidates) {
      if (_unavailableTrackIDs.contains(track.id)) continue;
      try {
        await _loadTrack(track, generation);
        return;
      } catch (error, stackTrace) {
        if (!_isCurrentLoad(generation)) return;
        _unavailableTrackIDs.add(track.id);
        _logger.warning(
          "Failed to load memory music track ${track.id}",
          error,
          stackTrace,
        );
      }
    }
    _status = _MemoryMusicPlaybackStatus.idle;
  }

  Future<void> toggleMuted() async {
    if (_isDisposed) return;
    final isMuted = !_isMuted;
    _isMuted = isMuted;
    notifyListeners();
    final synchronizePlayback = _synchronizePlayback(immediately: true);
    try {
      await _persistMuted(isMuted);
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to persist memories audio mute state",
        error,
        stackTrace,
      );
    }
    await synchronizePlayback;
  }

  Future<void> setAppActive(bool isActive) async {
    if (_setPauseReason(_MemoryMusicPauseReason.appBackground, !isActive)) {
      await _synchronizePlayback(immediately: !isActive);
    }
  }

  Future<void> setViewerActionPaused(bool isPaused) async {
    if (_setPauseReason(_MemoryMusicPauseReason.viewerAction, isPaused)) {
      await _synchronizePlayback();
    }
  }

  bool _setPauseReason(_MemoryMusicPauseReason reason, bool shouldPause) {
    return shouldPause
        ? _pauseReasons.add(reason)
        : _pauseReasons.remove(reason);
  }

  Future<void> _synchronizePlayback({bool immediately = false}) async {
    if (_isDisposed) return;
    final shouldPlay =
        _status == _MemoryMusicPlaybackStatus.ready &&
        !_isMuted &&
        _pauseReasons.isEmpty;
    try {
      if (shouldPlay) {
        await (immediately ? _player.playImmediately() : _player.play());
      } else {
        await (immediately ? _player.pauseImmediately() : _player.pause());
      }
    } catch (error, stackTrace) {
      if (_isDisposed) return;
      _logger.warning(
        "Failed to synchronize memory music playback",
        error,
        stackTrace,
      );
    }
  }

  Future<void> _ensureAudioSessionInitialized() =>
      _audioSessionInitialization ??= _initializeAudioSession();

  Future<void> _loadTrack(MemoryMusicTrack track, int generation) async {
    await _ensureAudioSessionInitialized();
    if (!_isCurrentLoad(generation)) return;
    await _player.load(track);
    if (!_isCurrentLoad(generation)) return;
    await _player.setLooping();
    if (!_isCurrentLoad(generation)) return;
    _status = _MemoryMusicPlaybackStatus.ready;
    await _synchronizePlayback();
  }

  Future<void> _initializeAudioSession() async {
    try {
      await _player.configureAudioSession();
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to configure the memory music audio session",
        error,
        stackTrace,
      );
    }
  }

  bool _isCurrentLoad(int generation) =>
      !_isDisposed && generation == _loadGeneration;

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_player.dispose());
    super.dispose();
  }
}
