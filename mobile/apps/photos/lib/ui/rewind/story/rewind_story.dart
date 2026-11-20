import "dart:math";

import "package:collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/story/rewind_composer.dart";
import "package:photos/ui/rewind/story/rewind_media.dart";
import "package:photos/ui/rewind/story/rewind_rituals.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";

class RewindStory {
  RewindStory._(this.pages, this._photos, this._outline, this.rituals);

  static const _lookahead = 3;
  static const _photoPatience = Duration(seconds: 20);

  static Future<RewindStory> prepare(rust.RewindReport report) async {
    final rituals = await RewindRituals.settled();
    return compose(
      rewindChapters(report, rituals),
      await RewindMedia.load(),
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
    for (final chapter in chapters) {
      final chapterPages = await chapter.compose(media);
      final chapterPhotos = media.takeHandedOut();
      pages.addAll(chapterPages);
      photos.addAll([for (final _ in chapterPages) chapterPhotos]);
    }
    return RewindStory._(pages, photos, [
      for (final chapter in chapters) ...chapter.keys,
    ], rituals);
  }

  final List<RewindPage> pages;
  final RewindRituals? rituals;
  final List<List<EnteFile>> _photos;
  final List<String> _outline;
  final _preloaded = Set<List<EnteFile>>.identity();

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

  void preloadFrom(int index) {
    for (var i = index; i < min(pages.length, index + _lookahead); i++) {
      if (_preloaded.add(_photos[i])) _photos[i].forEach(preloadRewindPhoto);
    }
  }
}
