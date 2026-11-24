import "dart:collection";
import "dart:math";

import "package:collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/pages/setup_page.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/story/rewind_composer.dart";
import "package:photos/ui/rewind/story/rewind_media.dart";
import "package:photos/ui/rewind/story/rewind_rituals.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_pixels.dart";

class RewindStory {
  RewindStory._(
    this.pages,
    this._photos,
    this._galleries,
    this._outline,
    this.rituals,
    this._blurryFaces,
  );

  static const _lookahead = 3;
  static const _cachers = 3;
  static const _cacheFailuresInARow = 3;
  static const _cachePauses = 4;
  static const _photoPatience = Duration(seconds: 20);

  static Future<RewindStory> prepare(rust.RewindReport report) async {
    final rituals = await RewindRituals.settled();
    return compose(
      rewindChapters(report, rituals),
      await RewindMedia.load(report),
      rituals: rituals,
    );
  }

  static Future<RewindStory> compose(
    List<RewindChapter> chapters,
    RewindMedia media, {
    RewindRituals? rituals,
  }) async {
    final pages = <RewindPage>[];
    final photos = <List<EnteFile>>[];
    final galleries = <List<EnteFile>>[];
    for (final chapter in chapters) {
      final chapterPages = await chapter.compose(media);
      final chapterPhotos = media.takeHandedOut();
      final chapterGalleries = media.takeGalleries();
      pages.addAll(chapterPages);
      photos.addAll([for (final _ in chapterPages) chapterPhotos]);
      galleries.addAll([for (final _ in chapterPages) chapterGalleries]);
    }
    return RewindStory._(
      pages,
      photos,
      galleries,
      [for (final chapter in chapters) ...chapter.keys],
      rituals,
      media.blurryFaces,
    );
  }

  final List<RewindPage> pages;
  final RewindRituals? rituals;
  final List<List<EnteFile>> _photos;
  final List<List<EnteFile>> _galleries;
  final List<String> _outline;
  final List<RewindBlurryFaces> _blurryFaces;
  final _preloaded = Set<List<EnteFile>>.identity();

  int get blurryFaceFiles => _blurryFaces.length;

  Future<bool> sharpenFaces() async {
    var sharpened = false;
    for (final blurry in _blurryFaces) {
      if (await RewindMedia.sharpen(blurry)) sharpened = true;
    }
    return sharpened;
  }

  int indexOf(String? key) =>
      max(0, pages.indexWhere((page) => page.key == key));

  String? resumeAt(String? key) {
    if (key == null || pages.any((page) => page.key == key)) return key;
    final position = _outline.indexOf(key);
    if (position < 0) return null;
    final later = _outline.skip(position + 1).toSet();
    return pages.firstWhereOrNull((page) => later.contains(page.key))?.key;
  }

  int resumeIndex(String? key) => indexOf(resumeAt(key));

  Future<bool> loadPhotosOf(List<RewindPage> shown) async {
    final cards = {
      for (final (i, page) in pages.indexed)
        if (shown.contains(page)) page.reelThumbnails ?? _photos[i],
    };
    final loaded = await Future.wait([
      for (final photos in cards)
        if (photos.isNotEmpty) _loadsAnyOf(photos),
    ]);
    return !loaded.contains(false);
  }

  static Future<bool> _loadsAnyOf(List<EnteFile> photos) async {
    final loaded = await Future.wait([
      for (final photo in photos)
        loadRewindPhoto(photo)
            .timeout(_photoPatience)
            .then((loaded) => loaded, onError: (Object _) => false),
    ]);
    return loaded.contains(true);
  }

  Future<({int cached, int total})> cachePhotos(
    int from,
    bool Function() isCurrent,
  ) async {
    final photos = _cacheOrder(from);
    final cache = RewindThumbnailCache(stopsAfterServerStall: true);
    final untouched = Queue.of(Iterable<int>.generate(photos.length));
    final retries = Queue<int>();
    final failed = <int>[];
    var cached = 0;
    var failures = 0;
    var triedUntouched = false;
    int? next() {
      if (untouched.isNotEmpty) {
        triedUntouched = true;
        return untouched.removeFirst();
      }
      return retries.isEmpty ? null : retries.removeFirst();
    }

    Future<void> cacher() async {
      while (failures < _cacheFailuresInARow &&
          !cache.serverStalled &&
          isCurrent()) {
        final index = next();
        if (index == null) return;
        if (await cache.save(photos[index])) {
          cached++;
          failures = 0;
        } else {
          failed.add(index);
          failures++;
        }
      }
    }

    var pauses = 0;
    while (true) {
      triedUntouched = false;
      await Future.wait([for (var i = 0; i < _cachers; i++) cacher()]);
      final retry = [...retries, ...failed];
      if (untouched.isEmpty && retry.isEmpty) break;
      if (cache.serverStalled || !isCurrent()) break;
      if (!triedUntouched && pauses == _cachePauses) break;
      await Future<void>.delayed(rewindRetryAfter(pauses));
      if (!triedUntouched) pauses++;
      retries
        ..clear()
        ..addAll(retry);
      failed.clear();
      failures = 0;
    }
    return (cached: cached, total: photos.length);
  }

  List<EnteFile> _cacheOrder(int from) {
    final order = [
      for (var step = 0; step < pages.length; step++)
        (from + step) % pages.length,
    ];
    final photos = <int, EnteFile>{};
    for (final photo in [
      for (final i in order) ..._pagePhotos(i),
      for (final i in order) ..._photos[i],
      for (final i in order) ..._galleries[i],
    ]) {
      if (photo.isUploaded) {
        photos.putIfAbsent(photo.uploadedFileID!, () => photo);
      }
    }
    return photos.values.toList();
  }

  List<EnteFile> _pagePhotos(int i) {
    final page = pages[i];
    if (page is SetupPage) return const [];
    final reel = page.reelThumbnails;
    if (reel == null) return _photos[i];
    return _hasChapterToItself(i) ? [...reel, ..._photos[i]] : reel;
  }

  bool _hasChapterToItself(int i) {
    for (final (j, page) in pages.indexed) {
      if (j != i && page is! SetupPage && identical(_photos[j], _photos[i])) {
        return false;
      }
    }
    return true;
  }

  void preloadFrom(int index) {
    for (var i = index; i < min(pages.length, index + _lookahead); i++) {
      if (_preloaded.add(_photos[i])) _photos[i].forEach(preloadRewindPhoto);
    }
  }
}
