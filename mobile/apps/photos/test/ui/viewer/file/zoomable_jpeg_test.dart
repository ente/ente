import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:image/image.dart" as img;
import "package:photos/core/cache/image_cache.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/ui/viewer/file/image_zoom/image_zoom_viewer.dart";
import "package:photos/ui/viewer/file/image_zoom/viewer_jpeg_image.dart";
import "package:photos/ui/viewer/file/zoomable_image.dart";

void main() {
  test("fit requests the smallest native JPEG size covering the photo", () {
    final jpeg = File("photo.jpg");
    final portrait = ViewerJpegImage.fit(jpeg, const Size(1080, 2340));
    final landscape = ViewerJpegImage.fit(jpeg, const Size(2340, 1080));

    final a54Photo = portrait.targetSizeFor(const Size(6120, 8160));
    expect((a54Photo.width, a54Photo.height), (1530, 2040));

    const panorama = Size(8639, 2159);
    final upright = portrait.targetSizeFor(panorama);
    final rotated = landscape.targetSizeFor(panorama);
    expect((upright.width, upright.height), (1080, 270));
    expect((rotated.width, rotated.height), (3240, 810));

    final small = portrait.targetSizeFor(const Size(640, 480));
    expect((small.width, small.height), (640, 480));
  });

  testWidgets(
    "oriented JPEG returns to fit when it loses selection during zoom",
    (tester) async {
      final directory = Directory.systemTemp.createTempSync("viewer_jpeg_");
      addTearDown(() => directory.deleteSync(recursive: true));
      final source = img.Image(width: 800, height: 600);
      source.exif.imageIfd.orientation = 6;
      final jpeg = File("${directory.path}/original.jpg")
        ..writeAsBytesSync(img.encodeJpg(source));
      final file = _DelayedDetailFile(jpeg);
      final photo = EnteFile()
        ..localID = "jpeg-viewer-test"
        ..title = "original.MP.JPG"
        ..fileType = FileType.image;
      FileLruCache.put("${photo.tag}falsefalse", file);
      final thumb = img.encodeJpg(img.Image(width: 3, height: 4));
      ThumbnailInMemoryLruCache.put(photo, thumb, thumbnailLargeSize);
      addTearDown(FileLruCache.clearAll);
      addTearDown(ThumbnailInMemoryLruCache.clearAll);

      final loaded = <File>[];
      Future<void> show({required bool selected, bool landscape = false}) =>
          tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(devicePixelRatio: 2),
                child: Center(
                  child: SizedBox(
                    width: landscape ? 100 : 60,
                    height: landscape ? 60 : 100,
                    child: ZoomableImage(
                      photo,
                      tagPrefix: "viewer",
                      isSelectedViewerPage: selected,
                      onFinalImageLoaded: loaded.add,
                    ),
                  ),
                ),
              ),
            ),
          );

      ImageZoomViewer viewer() =>
          tester.widget<ImageZoomViewer>(find.byType(ImageZoomViewer));

      Future<void> doubleTap() async {
        final center = tester.getCenter(find.byType(ImageZoomViewer));
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tapAt(center);
        await tester.pump();
      }

      await show(selected: true);
      await _pumpUntil(tester, () => loaded.isNotEmpty);
      expect(viewer().sourceImageSize, const Size(600, 800));
      final fit = viewer().imageProvider;
      expect(fit, ViewerJpegImage.fit(jpeg, const Size(120, 200)));
      final raw = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect((raw.width, raw.height), (150, 200));

      await doubleTap();
      await tester.pump(viewer().animationDuration ~/ 2);
      expect(viewer().controller!.isZoomed, isTrue);
      expect(imageCache.statusForKey(FileImage(file)).untracked, isTrue);
      await tester.pumpAndSettle();
      await _pumpUntil(tester, () => file.loadingDetail);
      expect(viewer().imageProvider, fit);
      await show(selected: false);
      file.allowDetail.complete();
      await _pumpUntil(
        tester,
        () => imageCache.statusForKey(FileImage(file)).keepAlive,
      );
      expect(viewer().imageProvider, fit);
      expect(viewer().controller!.isZoomed, isFalse);

      await show(selected: true);
      await doubleTap();
      await tester.pumpAndSettle();
      await _pumpUntil(tester, () => viewer().imageProvider is FileImage);
      expect(viewer().sourceImageSize, const Size(600, 800));
      await viewer().controller!.reset(animated: false);
      await _pumpUntil(tester, () => viewer().imageProvider == fit);

      await show(selected: true, landscape: true);
      final rotatedFit = ViewerJpegImage.fit(jpeg, const Size(200, 120));
      await _pumpUntil(tester, () => viewer().imageProvider == rotatedFit);
      expect(loaded, [same(file)]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
}

class _DelayedDetailFile extends Fake implements File {
  final File original;
  final allowDetail = Completer<void>();
  bool loadingDetail = false;

  _DelayedDetailFile(this.original);

  @override
  String get path => original.path;

  @override
  bool existsSync() => original.existsSync();

  @override
  Future<int> length() async => original.lengthSync();

  @override
  Future<Uint8List> readAsBytes() async {
    loadingDetail = true;
    await allowDetail.future;
    return original.readAsBytesSync();
  }
}
