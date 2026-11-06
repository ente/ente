import "dart:async";

import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/services/memories/just_audio_memory_music_player.dart";
import "package:photos/services/memories/memory_music_service.dart";

class RewindMusic extends ChangeNotifier {
  static final _logger = Logger("RewindMusic");

  JustAudioMemoryMusicPlayer? _player;
  var _muted = false;
  var _appActive = true;
  var _disposed = false;

  bool get muted => _muted;

  Future<void> start() async {
    final player = await _loadFirstTrack();
    if (player == null) return;
    if (_disposed) {
      await player.dispose();
      return;
    }
    _player = player;
    await _sync();
  }

  Future<JustAudioMemoryMusicPlayer?> _loadFirstTrack() async {
    JustAudioMemoryMusicPlayer? player;
    try {
      final tracks = await MemoryMusicService.instance.prepare();
      if (_disposed || tracks.isEmpty) return null;
      player = JustAudioMemoryMusicPlayer();
      await player.configureAudioSession();
      await player.load(tracks.first);
      return player;
    } catch (error, stackTrace) {
      _logger.warning("Failed to load Rewind music", error, stackTrace);
      await player?.dispose();
      return null;
    }
  }

  void toggleMuted() {
    _muted = !_muted;
    notifyListeners();
    unawaited(_sync());
  }

  set appActive(bool active) {
    if (active == _appActive) return;
    _appActive = active;
    unawaited(_sync());
  }

  Future<void> _sync() async {
    final player = _player;
    if (player == null || _disposed) return;
    if (_muted || !_appActive) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }
}
