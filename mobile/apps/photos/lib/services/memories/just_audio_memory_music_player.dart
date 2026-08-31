import "dart:async";

import "package:audio_session/audio_session.dart";
import "package:just_audio/just_audio.dart";
import "package:logging/logging.dart";
import "package:photos/models/memories/memory_music_track.dart";
import "package:photos/services/memories/memory_music_player.dart";
import "package:photos/services/remote_assets_service.dart";

class JustAudioMemoryMusicPlayer implements MemoryMusicPlayer {
  static const _fadeInDuration = Duration(milliseconds: 900);
  static const _fadeOutDuration = Duration(milliseconds: 250);
  static const _fadeSteps = 14;

  final AudioPlayer _player;
  final Logger _logger = Logger("JustAudioMemoryMusicPlayer");

  Future<void> _fadeQueue = Future<void>.value();
  int _fadeGeneration = 0;

  JustAudioMemoryMusicPlayer() : _player = AudioPlayer();

  @override
  Future<void> configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  @override
  Future<void> load(MemoryMusicTrack track) async {
    final file = await RemoteAssetsService.instance.getAsset(
      track.url,
      cacheFileName: track.cacheFileName,
    );
    await _player.setFilePath(file.path, preload: true);
  }

  @override
  Future<void> setLooping() => _player.setLoopMode(LoopMode.one);

  @override
  Future<void> play() {
    final generation = ++_fadeGeneration;
    return _enqueueFade(generation, () async {
      if (!_player.playing) {
        await _player.setVolume(0);
        if (generation != _fadeGeneration) return;
        _startPlayback();
      }
      await _fadeTo(1, _fadeInDuration, generation);
    });
  }

  @override
  Future<void> playImmediately() async {
    final generation = ++_fadeGeneration;
    await _player.setVolume(1);
    if (generation != _fadeGeneration) return;
    _startPlayback();
  }

  @override
  Future<void> pause() {
    final generation = ++_fadeGeneration;
    return _enqueueFade(generation, () async {
      if (!_player.playing) return;
      await _fadeTo(0, _fadeOutDuration, generation);
      if (generation == _fadeGeneration) await _player.pause();
    });
  }

  @override
  Future<void> pauseImmediately() {
    _fadeGeneration++;
    return _player.pause();
  }

  @override
  Future<void> dispose() async {
    await pauseImmediately();
    final generation = ++_fadeGeneration;
    await _enqueueFade(generation, _player.dispose);
  }

  Future<void> _fadeTo(
    double targetVolume,
    Duration duration,
    int generation,
  ) async {
    final initialVolume = _player.volume;
    final stepDuration = duration ~/ _fadeSteps;
    for (var step = 1; step <= _fadeSteps; step++) {
      await Future<void>.delayed(stepDuration);
      if (generation != _fadeGeneration) return;
      final progress = step / _fadeSteps;
      await _player.setVolume(
        initialVolume + (targetVolume - initialVolume) * progress,
      );
    }
  }

  void _startPlayback() {
    if (_player.playing) return;
    unawaited(
      _player.play().catchError((Object error, StackTrace stackTrace) {
        _logger.warning(
          "Failed to start memory music playback",
          error,
          stackTrace,
        );
      }),
    );
  }

  Future<void> _enqueueFade(int generation, Future<void> Function() operation) {
    final result = _fadeQueue.then((_) async {
      if (generation == _fadeGeneration) await operation();
    });
    _fadeQueue = result.catchError((Object _, StackTrace _) {});
    return result;
  }
}
