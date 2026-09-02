import "dart:async";
import "dart:convert";

import "package:crypto/crypto.dart";
import "package:dio/dio.dart";
import "package:logging/logging.dart";
import "package:photos/models/memories/memory_music_track.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:shared_preferences/shared_preferences.dart";

const _manifestURL = "https://music.ente.com/tracks.json";
const _manifestPreferenceKey = "memory_music_manifest";

String memoryMusicCacheFileName(String url) =>
    "memory-music-${sha256.convert(utf8.encode(url))}.mp3";

class MemoryMusicService {
  static final _logger = Logger("MemoryMusicService");
  static final instance = MemoryMusicService(
    preferences: ServiceLocator.instance.prefs,
    fetchManifest: () async {
      final response = await ServiceLocator.instance.nonEnteDio.get<Object?>(
        _manifestURL,
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      return response.data;
    },
    hasAsset: (url) => RemoteAssetsService.instance.hasAsset(
      url,
      cacheFileName: memoryMusicCacheFileName(url),
    ),
    cacheAsset: (url) async {
      await RemoteAssetsService.instance.getAsset(
        url,
        cacheFileName: memoryMusicCacheFileName(url),
      );
    },
    deleteAsset: (url) => RemoteAssetsService.instance.deleteAsset(
      url,
      cacheFileName: memoryMusicCacheFileName(url),
    ),
  );

  final SharedPreferences _preferences;
  final Future<Object?> Function() _fetchManifest;
  final Future<bool> Function(String url) _hasAsset;
  final Future<void> Function(String url) _cacheAsset;
  final Future<void> Function(String url) _deleteAsset;

  final Set<String> _availableURLs = {};
  final Map<String, Future<bool>> _assetDownloads = {};
  List<MemoryMusicTrack>? _tracks;
  Future<List<MemoryMusicTrack>>? _preparation;
  bool _manifestRefreshed = false;

  MemoryMusicService({
    required SharedPreferences preferences,
    required Future<Object?> Function() fetchManifest,
    required Future<bool> Function(String url) hasAsset,
    required Future<void> Function(String url) cacheAsset,
    required Future<void> Function(String url) deleteAsset,
  }) : _preferences = preferences,
       _fetchManifest = fetchManifest,
       _hasAsset = hasAsset,
       _cacheAsset = cacheAsset,
       _deleteAsset = deleteAsset;

  Future<List<MemoryMusicTrack>> prepare() =>
      _preparation ??= _prepare().whenComplete(() => _preparation = null);

  Future<List<MemoryMusicTrack>> _prepare() async {
    _tracks ??= _readCachedManifest();
    if (!_manifestRefreshed) await _refreshManifest();
    return _availableTracks(_tracks!);
  }

  List<MemoryMusicTrack> _readCachedManifest() {
    final manifest = _preferences.getString(_manifestPreferenceKey);
    if (manifest == null) return const [];
    try {
      return _parseManifest(jsonDecode(manifest));
    } catch (error, stackTrace) {
      _logger.warning(
        "Ignoring invalid cached memory music manifest",
        error,
        stackTrace,
      );
      return const [];
    }
  }

  Future<void> _refreshManifest() async {
    try {
      final manifest = await _fetchManifest();
      final tracks = _parseManifest(manifest);
      final previousTracks = _tracks!;
      _tracks = tracks;
      _manifestRefreshed = true;
      await _persistAndCleanUp(manifest, previousTracks, tracks);
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to refresh memory music manifest",
        error,
        stackTrace,
      );
    }
  }

  Future<void> _persistAndCleanUp(
    Object? manifest,
    List<MemoryMusicTrack> previousTracks,
    List<MemoryMusicTrack> tracks,
  ) async {
    try {
      final saved = await _preferences.setString(
        _manifestPreferenceKey,
        jsonEncode(manifest),
      );
      if (!saved) {
        _logger.warning("Failed to cache memory music manifest");
        return;
      }
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to cache memory music manifest",
        error,
        stackTrace,
      );
      return;
    }

    final currentURLs = tracks.map((track) => track.url).toSet();
    final removedURLs = previousTracks
        .map((track) => track.url)
        .toSet()
        .difference(currentURLs);
    await Future.wait(removedURLs.map(_deleteRemovedAsset));
  }

  Future<void> _deleteRemovedAsset(String url) async {
    try {
      await _deleteAsset(url);
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to delete removed memory music asset $url",
        error,
        stackTrace,
      );
    }
  }

  Future<List<MemoryMusicTrack>> _availableTracks(
    List<MemoryMusicTrack> tracks,
  ) async {
    final currentURLs = tracks.map((track) => track.url).toSet();
    _availableURLs.retainAll(currentURLs);
    await Future.wait(
      currentURLs
          .where(
            (url) =>
                !_availableURLs.contains(url) &&
                !_assetDownloads.containsKey(url),
          )
          .map(_findCachedAsset),
    );

    final downloads = <Future<bool>>[
      for (final url in currentURLs)
        if (!_availableURLs.contains(url)) _downloadAsset(url),
    ];
    if (_availableURLs.isEmpty && downloads.isNotEmpty) {
      await Stream.fromFutures(
        downloads,
      ).firstWhere((didDownload) => didDownload, orElse: () => false);
    }

    return tracks
        .where((track) => _availableURLs.contains(track.url))
        .toList(growable: false);
  }

  Future<void> _findCachedAsset(String url) async {
    try {
      if (await _hasAsset(url)) _availableURLs.add(url);
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to check memory music asset $url",
        error,
        stackTrace,
      );
    }
  }

  Future<bool> _downloadAsset(String url) =>
      _assetDownloads[url] ??= _cacheAssetURL(url).whenComplete(() {
        _assetDownloads.remove(url);
      });

  Future<bool> _cacheAssetURL(String url) async {
    try {
      await _cacheAsset(url);
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to cache memory music asset $url",
        error,
        stackTrace,
      );
      return false;
    }

    if (!_tracks!.any((track) => track.url == url)) {
      return false;
    }
    _availableURLs.add(url);
    return true;
  }

  List<MemoryMusicTrack> _parseManifest(Object? manifest) {
    if (manifest is! Map<String, dynamic>) {
      throw const FormatException("Memory music manifest must be an object");
    }
    final entries = manifest["tracks"];
    if (entries is! List) {
      throw const FormatException("Memory music manifest needs tracks");
    }

    final ids = <String>{};
    final tracks = <MemoryMusicTrack>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException("Memory music track must be an object");
      }
      final id = entry["id"];
      final url = entry["url"];
      final title = entry["title"];
      final artist = entry["artist"];
      if (id is! String || id.trim().isEmpty) {
        throw const FormatException("Memory music track needs an ID");
      }
      if (!ids.add(id)) {
        throw FormatException("Duplicate memory music track ID: $id");
      }
      if (url is! String || !_isValidTrackURL(url)) {
        throw FormatException("Invalid memory music track URL for $id");
      }
      if (title != null && title is! String) {
        throw FormatException("Invalid memory music track title for $id");
      }
      if (artist != null && artist is! String) {
        throw FormatException("Invalid memory music track artist for $id");
      }
      tracks.add(
        MemoryMusicTrack(
          id: id,
          url: url,
          title: title as String?,
          artist: artist as String?,
        ),
      );
    }
    tracks.sort((a, b) => a.id.compareTo(b.id));
    return tracks;
  }

  bool _isValidTrackURL(String value) {
    final url = Uri.tryParse(value);
    return url != null &&
        url.scheme == "https" &&
        url.host.isNotEmpty &&
        url.path.toLowerCase().endsWith(".mp3");
  }
}
