import "dart:async";
import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:photos/services/memories/memory_music_service.dart";
import "package:shared_preferences/shared_preferences.dart";

const _manifestPreferenceKey = "memory_music_manifest";
const _cachedURL = "https://music.ente.com/cached.mp3";
const _newURL = "https://music.ente.com/new.mp3";
const _sharedURL = "https://music.ente.com/shared.mp3";

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  test("sorts a valid manifest and checks each cached URL once", () async {
    final manifest = _manifest([
      _track("z-track", _sharedURL, title: "Zed"),
      _track("a-track", _sharedURL, artist: "Artist"),
      _track("middle-track", _newURL),
    ]);
    final checkedURLs = <String>[];
    final service = _service(
      preferences,
      fetchManifest: () async => manifest,
      hasAsset: (url) async {
        checkedURLs.add(url);
        return true;
      },
    );

    final tracks = await service.prepare();

    expect(tracks.map((track) => track.id), [
      "a-track",
      "middle-track",
      "z-track",
    ]);
    expect(tracks.first.artist, "Artist");
    expect(tracks.last.title, "Zed");
    expect(checkedURLs, unorderedEquals([_sharedURL, _newURL]));
    expect(
      jsonDecode(preferences.getString(_manifestPreferenceKey)!),
      manifest,
    );
  });

  test("uses a cached manifest after failure and retries refresh", () async {
    final cachedManifest = _manifest([_track("cached", _cachedURL)]);
    final refreshedManifest = _manifest([_track("new", _newURL)]);
    final cachedManifestJSON = jsonEncode(cachedManifest);
    await preferences.setString(_manifestPreferenceKey, cachedManifestJSON);
    var fetchCalls = 0;
    final deletedURLs = <String>[];
    final service = _service(
      preferences,
      fetchManifest: () async {
        fetchCalls++;
        if (fetchCalls == 1) throw StateError("offline");
        return refreshedManifest;
      },
      deleteAsset: (url) async => deletedURLs.add(url),
    );

    final fallbackTracks = await service.prepare();

    expect(fallbackTracks.map((track) => track.id), ["cached"]);
    expect(preferences.getString(_manifestPreferenceKey), cachedManifestJSON);
    expect(deletedURLs, isEmpty);

    final refreshedTracks = await service.prepare();

    expect(refreshedTracks.map((track) => track.id), ["new"]);
    expect(fetchCalls, 2);
    expect(deletedURLs, [_cachedURL]);
    expect(
      jsonDecode(preferences.getString(_manifestPreferenceKey)!),
      refreshedManifest,
    );
  });

  for (final invalidManifest in <(String, Object?)>[
    (
      "invalid entry",
      _manifest([
        <String, dynamic>{"id": "broken", "url": 42},
      ]),
    ),
    (
      "duplicate IDs",
      _manifest([
        _track("duplicate", "https://music.ente.com/first.mp3"),
        _track("duplicate", "https://music.ente.com/second.mp3"),
      ]),
    ),
  ]) {
    test("${invalidManifest.$1} preserves the cached manifest", () async {
      final cachedManifest = _manifest([_track("cached", _cachedURL)]);
      final cachedManifestJSON = jsonEncode(cachedManifest);
      await preferences.setString(_manifestPreferenceKey, cachedManifestJSON);
      final deletedURLs = <String>[];
      final service = _service(
        preferences,
        fetchManifest: () async => invalidManifest.$2,
        deleteAsset: (url) async => deletedURLs.add(url),
      );

      final tracks = await service.prepare();

      expect(tracks.map((track) => track.id), ["cached"]);
      expect(preferences.getString(_manifestPreferenceKey), cachedManifestJSON);
      expect(deletedURLs, isEmpty);
    });
  }

  test("an empty manifest removes each previously referenced URL", () async {
    await preferences.setString(
      _manifestPreferenceKey,
      jsonEncode(
        _manifest([
          _track("cached-a", _cachedURL),
          _track("cached-b", _cachedURL),
          _track("shared", _sharedURL),
        ]),
      ),
    );
    final deletedURLs = <String>[];
    final emptyManifest = _manifest([]);
    final service = _service(
      preferences,
      fetchManifest: () async => emptyManifest,
      deleteAsset: (url) async => deletedURLs.add(url),
    );

    final tracks = await service.prepare();

    expect(tracks, isEmpty);
    expect(deletedURLs, unorderedEquals([_cachedURL, _sharedURL]));
    expect(
      jsonDecode(preferences.getString(_manifestPreferenceKey)!),
      emptyManifest,
    );
  });

  test("removes only URLs no longer shared by the new manifest", () async {
    await preferences.setString(
      _manifestPreferenceKey,
      jsonEncode(
        _manifest([
          _track("removed", _cachedURL),
          _track("old-shared-id", _sharedURL),
        ]),
      ),
    );
    final deletedURLs = <String>[];
    final service = _service(
      preferences,
      fetchManifest: () async => _manifest([
        _track("new-shared-id", _sharedURL),
        _track("new", _newURL),
      ]),
      deleteAsset: (url) async => deletedURLs.add(url),
    );

    final tracks = await service.prepare();

    expect(tracks.map((track) => track.id), ["new", "new-shared-id"]);
    expect(deletedURLs, [_cachedURL]);
  });

  test("returns cached tracks without waiting for a download", () async {
    final downloadStarted = Completer<void>();
    final finishDownload = Completer<void>();
    addTearDown(() {
      if (!finishDownload.isCompleted) finishDownload.complete();
    });
    final service = _service(
      preferences,
      fetchManifest: () async =>
          _manifest([_track("cached", _cachedURL), _track("new", _newURL)]),
      hasAsset: (url) async => url == _cachedURL,
      cacheAsset: (url) async {
        expect(url, _newURL);
        downloadStarted.complete();
        await finishDownload.future;
      },
    );

    final preparation = service.prepare();
    await downloadStarted.future.timeout(const Duration(seconds: 1));

    expect(
      (await preparation.timeout(
        const Duration(seconds: 1),
      )).map((track) => track.id),
      ["cached"],
    );

    finishDownload.complete();
  });

  test("returns after the first download succeeds", () async {
    const slowURL = "https://music.ente.com/slow.mp3";
    final slowDownloadStarted = Completer<void>();
    final finishSlowDownload = Completer<void>();
    addTearDown(() {
      if (!finishSlowDownload.isCompleted) finishSlowDownload.complete();
    });
    final service = _service(
      preferences,
      fetchManifest: () async =>
          _manifest([_track("ready", _newURL), _track("slow", slowURL)]),
      hasAsset: (_) async => false,
      cacheAsset: (url) async {
        if (url == slowURL) {
          slowDownloadStarted.complete();
          await finishSlowDownload.future;
        }
      },
    );

    final preparation = service.prepare();
    await slowDownloadStarted.future.timeout(const Duration(seconds: 1));

    expect(
      (await preparation.timeout(
        const Duration(seconds: 1),
      )).map((track) => track.id),
      ["ready"],
    );

    finishSlowDownload.complete();
  });

  test("retries failed downloads without refetching the manifest", () async {
    var fetchCalls = 0;
    var cacheAttempts = 0;
    final service = _service(
      preferences,
      fetchManifest: () async {
        fetchCalls++;
        return _manifest([_track("track", _newURL)]);
      },
      hasAsset: (_) async => false,
      cacheAsset: (_) async {
        cacheAttempts++;
        if (cacheAttempts == 1) throw StateError("download failed");
      },
    );

    expect(await service.prepare(), isEmpty);
    expect((await service.prepare()).map((track) => track.id), ["track"]);
    expect(fetchCalls, 1);
    expect(cacheAttempts, 2);
  });

  test("concurrent preparation shares one manifest fetch", () async {
    final fetchStarted = Completer<void>();
    final finishFetch = Completer<void>();
    var fetchCalls = 0;
    var cacheCalls = 0;
    final service = _service(
      preferences,
      fetchManifest: () async {
        fetchCalls++;
        fetchStarted.complete();
        await finishFetch.future;
        return _manifest([_track("track", _newURL)]);
      },
      cacheAsset: (_) async => cacheCalls++,
      hasAsset: (_) async => false,
    );

    final firstPreparation = service.prepare();
    await fetchStarted.future;
    final secondPreparation = service.prepare();

    expect(fetchCalls, 1);

    finishFetch.complete();
    final results = await Future.wait([firstPreparation, secondPreparation]);

    expect(results[0].map((track) => track.id), ["track"]);
    expect(results[1].map((track) => track.id), ["track"]);
    expect(cacheCalls, 1);
  });
}

MemoryMusicService _service(
  SharedPreferences preferences, {
  required Future<Object?> Function() fetchManifest,
  Future<bool> Function(String url)? hasAsset,
  Future<void> Function(String url)? cacheAsset,
  Future<void> Function(String url)? deleteAsset,
}) {
  return MemoryMusicService(
    preferences: preferences,
    fetchManifest: fetchManifest,
    hasAsset: hasAsset ?? (_) async => true,
    cacheAsset: cacheAsset ?? (_) async {},
    deleteAsset: deleteAsset ?? (_) async {},
  );
}

Map<String, dynamic> _manifest(List<Map<String, dynamic>> tracks) => {
  "tracks": tracks,
};

Map<String, dynamic> _track(
  String id,
  Object url, {
  String? title,
  String? artist,
}) => {"id": id, "url": url, "title": ?title, "artist": ?artist};
