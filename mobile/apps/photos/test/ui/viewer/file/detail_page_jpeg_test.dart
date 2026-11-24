import "dart:async";
import "dart:io";

import "package:dio/dio.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:image/image.dart" as img;
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/cache/image_cache.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/constants.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/viewer/album_slideshow/album_slideshow_page.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/file/image_zoom/image_zoom_viewer.dart";
import "package:photos/ui/viewer/file/image_zoom/viewer_jpeg_image.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const viewport = Size(320, 500);
  final files = <EnteFile>[];
  final previews = <ViewerJpegImage>[];
  final thumbnail = img.encodeJpg(img.Image(width: 32, height: 21));

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    ServiceLocator.instance.init(
      await SharedPreferences.getInstance(),
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1",
        buildNumber: "1",
      ),
    );
  });

  setUp(() {
    files.clear();
    previews.clear();
    final directory = Directory.systemTemp.createTempSync("viewer-jpegs-");
    final bytes = img.encodeJpg(img.Image(width: 960, height: 640));
    for (var id = 0; id < 4; id++) {
      final photo = EnteFile()
        ..localID = "photo-$id"
        ..title = "photo-$id.jpg"
        ..fileType = FileType.image;
      final file = File("${directory.path}/${photo.title}")
        ..writeAsBytesSync(bytes);
      FileLruCache.put("${photo.tag}falsefalse", file);
      ThumbnailInMemoryLruCache.put(photo, thumbnail, thumbnailSmallSize);
      ThumbnailInMemoryLruCache.put(photo, thumbnail, thumbnailLargeSize);
      files.add(photo);
      previews.add(ViewerJpegImage.fit(file, viewport));
    }
    addTearDown(() {
      FileLruCache.clearAll();
      ThumbnailInMemoryLruCache.clearAll();
      imageCache.clear();
      directory.deleteSync(recursive: true);
    });
  });

  Future<void> openPage(WidgetTester tester, Widget page) async {
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      "dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle",
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
    tester.view
      ..physicalSize = viewport
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: darkThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: page,
      ),
    );
  }

  DetailPage detailPage(List<EnteFile> items) => DetailPage(
    DetailPageConfiguration(
      items,
      1,
      "viewer-test",
      mode: DetailPageMode.selection,
      onSelectionRemoved: (_) {},
    ),
  );

  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    for (var frame = 0; frame < 100 && !ready(); frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(ready(), isTrue);
  }

  testWidgets("swiping between JPEGs reuses their fitted previews", (
    tester,
  ) async {
    await openPage(tester, detailPage(files));
    final viewer = find.byType(ImageZoomViewer).hitTestable();
    ImageZoomViewer visible() => tester.widget<ImageZoomViewer>(viewer);
    await waitFor(
      tester,
      () => previews
          .take(3)
          .every((preview) => imageCache.statusForKey(preview).keepAlive),
    );
    expect(visible().imageProvider, previews[1]);
    expect(imageCache.statusForKey(previews.last).untracked, isTrue);
    expect(
      previews.every(
        (preview) => imageCache.statusForKey(FileImage(preview.file)).untracked,
      ),
      isTrue,
    );
    for (final index in [2, 1]) {
      await tester.drag(viewer, Offset(index == 2 ? -250 : 250, 0));
      await tester.pumpAndSettle();
      await waitFor(tester, () => visible().imageProvider == previews[index]);
      if (index == 2) {
        await waitFor(
          tester,
          () => imageCache.statusForKey(previews.last).keepAlive,
        );
        final center = tester.getCenter(viewer);
        final detail = FileImage(previews[index].file);
        Future<void> pinch({required bool returnToFit}) async {
          final left = await tester.startGesture(center - const Offset(40, 0));
          final right = await tester.startGesture(center + const Offset(40, 0));
          await tester.pump();
          await left.moveTo(center - const Offset(80, 0));
          await right.moveTo(center + const Offset(80, 0));
          await tester.pump(const Duration(seconds: 1));
          expect(visible().controller!.transform.scale, closeTo(2.0, 0.01));
          expect(imageCache.statusForKey(detail).untracked, isTrue);
          if (returnToFit) {
            await left.moveTo(center - const Offset(40, 0));
            await right.moveTo(center + const Offset(40, 0));
          }
          await left.up();
          await right.up();
        }

        await pinch(returnToFit: true);
        await tester.pumpAndSettle();
        expect(visible().controller!.isZoomed, isFalse);
        expect(imageCache.statusForKey(detail).untracked, isTrue);

        await pinch(returnToFit: false);
        await waitFor(tester, () => visible().imageProvider == detail);
        expect(visible().controller!.transform.scale, closeTo(2.0, 0.01));
        await visible().controller!.reset(animated: false);
        await waitFor(tester, () => visible().imageProvider == previews[index]);
      }
    }
    const landscape = Size(500, 320);
    tester.view.physicalSize = landscape;
    await tester.pump();
    await waitFor(
      tester,
      () => previews
          .take(3)
          .every(
            (preview) => imageCache
                .statusForKey(ViewerJpegImage.fit(preview.file, landscape))
                .keepAlive,
          ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets("JPEG neighbors warm when a video page settles", (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    // Keep the video's disk cache pending while the JPEGs load.
    final cacheDirectory = Completer<String>();
    messenger.setMockMethodCallHandler(
      const MethodChannel("plugins.flutter.io/path_provider"),
      (_) => cacheDirectory.future,
    );

    EnteFile video(int id) {
      final file = EnteFile()
        ..generatedID = id
        ..title = "video-$id.mp4"
        ..fileType = FileType.video;
      ThumbnailInMemoryLruCache.put(file, thumbnail, thumbnailSmallSize);
      return file;
    }

    await openPage(
      tester,
      detailPage([files.first, video(1), video(2), files.last]),
    );
    await waitFor(
      tester,
      () => imageCache.statusForKey(previews.first).keepAlive,
    );
    expect(imageCache.statusForKey(previews.last).untracked, isTrue);

    final pageView = find.byType(PageView);
    final controller = tester.widget<PageView>(pageView).controller!;
    final drag = await tester.startGesture(tester.getCenter(pageView));
    await drag.moveBy(const Offset(-30, 0));
    await drag.moveBy(const Offset(-190, 0));
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.page!.round(), 2);
    expect(imageCache.statusForKey(previews.last).untracked, isTrue);
    await drag.up();
    await waitFor(
      tester,
      () => imageCache.statusForKey(previews.last).keepAlive,
    );
    expect(controller.position.isScrollingNotifier.value, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets("album slideshow decodes each JPEG only when displayed", (
    tester,
  ) async {
    await openPage(tester, AlbumSlideshowPage(files: files, title: "Album"));

    Future<void> expectCurrent(int index) async {
      await waitFor(
        tester,
        () => tester
            .widgetList<ImageZoomViewer>(find.byType(ImageZoomViewer))
            .any((viewer) => viewer.imageProvider == previews[index]),
      );
      expect(imageCache.statusForKey(previews[index + 1]).untracked, isTrue);
    }

    await expectCurrent(0);
    await tester.pump(
      Duration(seconds: localSettings.albumSlideshowDurationSeconds),
    );
    await expectCurrent(1);
    await tester.tapAt(const Offset(310, 250));
    await tester.pump();
    await expectCurrent(2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
