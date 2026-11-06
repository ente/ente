import "dart:math";

import "package:photos/models/file/file.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/story/rewind_composer.dart";
import "package:photos/ui/rewind/story/rewind_media.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";

class RewindStory {
  RewindStory._(this.pages, this._photos);

  static const _lookahead = 3;

  static Future<RewindStory> prepare(
    rust.RewindReport report, {
    Future<RewindMedia> Function() media = RewindMedia.load,
  }) async => compose(rewindChapters(report), await media());

  static Future<RewindStory> compose(
    List<RewindChapter> chapters,
    RewindMedia media,
  ) async {
    final pages = <RewindPage>[];
    final photos = <List<EnteFile>>[];
    for (final chapter in chapters) {
      final chapterPages = await chapter.compose(media);
      final chapterPhotos = media.takeHandedOut();
      pages.addAll(chapterPages);
      photos.addAll([for (final _ in chapterPages) chapterPhotos]);
    }
    return RewindStory._(pages, photos);
  }

  final List<RewindPage> pages;
  final List<List<EnteFile>> _photos;
  final _preloaded = Set<List<EnteFile>>.identity();

  int indexOf(String? key) =>
      max(0, pages.indexWhere((page) => page.key == key));

  void preloadFrom(int index) {
    for (var i = index; i < min(pages.length, index + _lookahead); i++) {
      if (_preloaded.add(_photos[i])) _photos[i].forEach(preloadRewindPhoto);
    }
  }
}
