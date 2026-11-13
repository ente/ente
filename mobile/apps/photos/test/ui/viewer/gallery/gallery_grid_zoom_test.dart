import "dart:async";

import "package:dio/dio.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/gallery/gallery_groups.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import "package:photos/ui/viewer/gallery/component/group/group_header_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:photos/ui/viewer/gallery/gallery_grid_zoom.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      preferences,
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );
    try {
      await Configuration.instance.init(preferences);
    } catch (_) {}
  });

  setUp(() async {
    await localSettings.setGalleryLayoutType(GalleryLayoutType.grid);
    await localSettings.setPhotoGridSize(4);
  });

  testWidgets(
    "morphs during a pinch and commits the deep focal anchor only on release",
    (tester) async {
      final fixture = _ZoomFixture();
      addTearDown(fixture.controller.dispose);
      await fixture.mount(tester);
      const anchorIndex = 806;
      const fraction = 0.3;
      const focalY = 300.0;
      final source = fixture.groups.gridZoomLayout(
        columns: 4,
        headerExtent: GalleryGroups.spacing,
      );
      final sourceTile = source.tileForIndex(anchorIndex)!;
      final scrollOffset =
          _ZoomFixture.contentTop +
          sourceTile.rect.top +
          sourceTile.rect.height * fraction -
          focalY;
      fixture.controller.jumpTo(scrollOffset);
      await tester.pump();
      final focalX = sourceTile.rect.center.dx;
      final first = await tester.startGesture(
        Offset(focalX - 80, focalY),
        pointer: 1,
      );
      final second = await tester.startGesture(
        Offset(focalX + 80, focalY),
        pointer: 2,
      );
      await tester.pump();
      expect(_overlay, findsOneWidget);
      final tileFinder = find.byKey(
        const ValueKey(("gallery-grid-zoom-tile", anchorIndex)),
      );
      final startRect = tester.getRect(tileFinder);
      expect(startRect.width, closeTo(source.tileExtent, 0.001));
      expect(
        startRect.top + startRect.height * fraction,
        closeTo(focalY, 0.001),
      );

      await first.moveTo(Offset(focalX - 64, focalY));
      await second.moveTo(Offset(focalX + 64, focalY));
      await tester.pump();
      final intermediate = tester.getRect(tileFinder);
      final target = fixture.groups.gridZoomLayout(
        columns: 5,
        headerExtent: GalleryGroups.spacing,
      );
      expect(
        intermediate.width,
        closeTo((startRect.width + target.tileExtent) / 2, 0.001),
      );
      expect(
        intermediate.top + intermediate.height * fraction,
        closeTo(focalY, 0.001),
      );
      expect(fixture.commits, isEmpty);
      expect(fixture.controller.offset, scrollOffset);

      await first.moveTo(Offset(focalX - 50, focalY));
      await second.moveTo(Offset(focalX + 50, focalY));
      await tester.pump();
      expect(fixture.commits, isEmpty);
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final targetTile = target.tileForIndex(anchorIndex)!;
      final targetOffset =
          _ZoomFixture.contentTop +
          targetTile.rect.top +
          targetTile.rect.height * fraction -
          focalY;
      expect(fixture.commits, hasLength(1));
      expect(fixture.commits.single.$1, 5);
      expect(fixture.commits.single.$2, closeTo(targetOffset, 0.001));
      expect(fixture.controller.offset, closeTo(targetOffset, 0.001));
      expect(fixture.groups.crossAxisCount, 5);
      expect(_overlay, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets("a cancelled morph restores the gallery without committing", (
    tester,
  ) async {
    final fixture = _ZoomFixture();
    addTearDown(fixture.controller.dispose);
    await fixture.mount(tester);
    fixture.controller.jumpTo(700);
    await tester.pump();
    final first = await tester.startGesture(const Offset(170, 280), pointer: 1);
    final second = await tester.startGesture(
      const Offset(330, 280),
      pointer: 2,
    );
    await first.moveTo(const Offset(195, 280));
    await second.moveTo(const Offset(305, 280));
    await tester.pump();
    expect(_overlay, findsOneWidget);
    await first.cancel();
    await second.up();
    await tester.pumpAndSettle();
    expect(_overlay, findsNothing);
    expect(fixture.commits, isEmpty);
    expect(fixture.controller.offset, 700);
    expect(fixture.groups.crossAxisCount, 4);

    await tester.drag(
      find.byKey(const ValueKey("gallery-scroll")),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(fixture.controller.offset, greaterThan(700));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    "selection stays aligned through justified morphs and clearing it cancels",
    (tester) async {
      for (final sourceLayout in [
        GalleryLayoutType.grid,
        GalleryLayoutType.justified,
      ]) {
        await localSettings.setPhotoGridSize(3);
        await localSettings.setGalleryLayoutType(sourceLayout);
        final selection = SelectedFiles();
        final fixture = _ZoomFixture(
          fileCount: 9,
          leadingExtent: 56,
          groupType: GroupType.day,
          selectedFiles: selection,
        );
        addTearDown(selection.dispose);
        addTearDown(fixture.controller.dispose);
        selection.selectAll(fixture.files.toSet());
        await fixture.mount(tester);
        final sourceTile = fixture.groups
            .gridZoomLayout(
              columns: fixture.groups.crossAxisCount,
              headerExtent: fixture.headerExtent,
            )
            .tileForIndex(0)!;
        final focalPoint =
            sourceTile.rect.center + Offset(0, fixture.leadingExtent);
        const halfSpan = 25.0;
        final first = await tester.startGesture(
          focalPoint - const Offset(halfSpan, 0),
          pointer: 1,
        );
        final second = await tester.startGesture(
          focalPoint + const Offset(halfSpan, 0),
          pointer: 2,
        );
        await tester.pump();
        final tile = find.byKey(const ValueKey(("gallery-grid-zoom-tile", 0)));
        final initialSize = tester.getRect(tile).size;
        final marker = find.byKey(
          const ValueKey(("gallery-grid-zoom-selection", 0)),
        );
        final shade = find.byKey(
          const ValueKey(("gallery-grid-zoom-selection-shade", 0)),
        );
        for (final scale
            in sourceLayout == GalleryLayoutType.grid
                ? [1.4, 2.4]
                : [0.8, 0.6]) {
          await first.moveTo(focalPoint - Offset(halfSpan * scale, 0));
          await second.moveTo(focalPoint + Offset(halfSpan * scale, 0));
          await tester.pump();
          final tileRect = tester.getRect(tile);
          final markerRect = tester.getRect(marker);
          expect(tileRect.size, isNot(initialSize));
          expect(markerRect.width, closeTo(16, 0.001));
          expect(markerRect.height, closeTo(16, 0.001));
          expect(markerRect.right, closeTo(tileRect.right - 4, 0.001));
          expect(markerRect.top, closeTo(tileRect.top + 4, 0.001));
          expect(tester.getRect(shade), tileRect);
          expect(
            tester.widget<ColoredBox>(shade).color,
            const Color.fromARGB(102, 0, 0, 0),
          );
          expect(
            tester
                .widget<SelectAllStatusIcon>(
                  find.descendant(
                    of: marker,
                    matching: find.byType(SelectAllStatusIcon),
                  ),
                )
                .isSelected,
            isTrue,
          );
          final selectedHeader = find.descendant(
            of: find.descendant(
              of: _overlay,
              matching: find.byType(GroupHeaderWidget),
            ),
            matching: find.byType(SelectAllStatusIcon),
          );
          expect(selectedHeader, findsOneWidget);
          expect(
            tester.widget<SelectAllStatusIcon>(selectedHeader).isSelected,
            isTrue,
          );
          expect(selection.files, unorderedEquals(fixture.files));
        }

        selection.clearAll(fireEvent: false);
        await tester.pump();
        expect(_overlay, findsNothing);
        await first.up();
        await second.up();
        await tester.pumpAndSettle();
        expect(fixture.commits, isEmpty);
        expect(selection.files, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets("morphs into the justified layout and back to three columns", (
    tester,
  ) async {
    await localSettings.setPhotoGridSize(3);
    final fixture = _ZoomFixture();
    addTearDown(fixture.controller.dispose);
    await fixture.mount(tester);
    const anchorIndex = 31;
    const fraction = 0.5;
    const focalY = 300.0;
    final source = fixture.groups.gridZoomLayout(
      columns: 3,
      headerExtent: GalleryGroups.spacing,
    );
    final sourceTile = source.tileForIndex(anchorIndex)!;
    final target = fixture.groups.gridZoomLayout(
      columns: 2,
      headerExtent: GalleryGroups.spacing,
    );
    final targetTile = target.tileForIndex(anchorIndex)!;
    final initialOffset =
        _ZoomFixture.contentTop + sourceTile.rect.center.dy - focalY;
    fixture.controller.jumpTo(initialOffset);
    await tester.pump();
    final focalX = sourceTile.rect.center.dx;
    final first = await tester.startGesture(
      Offset(focalX - 50, focalY),
      pointer: 1,
    );
    final second = await tester.startGesture(
      Offset(focalX + 50, focalY),
      pointer: 2,
    );
    await first.moveTo(Offset(focalX - 60, focalY));
    await second.moveTo(Offset(focalX + 60, focalY));
    await tester.pump();
    final tileFinder = find.byKey(
      const ValueKey(("gallery-grid-zoom-tile", anchorIndex)),
    );
    final intermediate = tester.getRect(tileFinder);
    expect(
      intermediate.width,
      closeTo((sourceTile.rect.width * 3 + targetTile.rect.width) / 4, 0.001),
    );
    expect(
      intermediate.height,
      closeTo((sourceTile.rect.height * 3 + targetTile.rect.height) / 4, 0.001),
    );
    expect(intermediate.center.dy, closeTo(focalY, 0.001));
    expect(fixture.commits, isEmpty);
    await first.moveTo(Offset(focalX - 100, focalY));
    await second.moveTo(Offset(focalX + 100, focalY));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(fixture.commits.single.$1, 2);
    expect(fixture.groups.layoutType, GalleryLayoutType.justified);
    expect(
      fixture.controller.offset,
      closeTo(
        _ZoomFixture.contentTop +
            targetTile.rect.top +
            targetTile.rect.height * fraction -
            focalY,
        0.001,
      ),
    );
    expect(_overlay, findsNothing);

    final justified = fixture.groups.gridZoomLayout(
      columns: 2,
      headerExtent: GalleryGroups.spacing,
    );
    final anchor = justified.tileForIndex(anchorIndex)!;
    final nextFocalX = anchor.rect.center.dx;
    final halfSpan =
        (nextFocalX < 200 ? nextFocalX : 400 - nextFocalX).clamp(0, 40) * 0.8;
    final third = await tester.startGesture(
      Offset(nextFocalX - halfSpan, focalY),
      pointer: 3,
    );
    final fourth = await tester.startGesture(
      Offset(nextFocalX + halfSpan, focalY),
      pointer: 4,
    );
    await third.moveTo(Offset(nextFocalX - halfSpan * 0.65, focalY));
    await fourth.moveTo(Offset(nextFocalX + halfSpan * 0.65, focalY));
    await tester.pump();
    expect(_overlay, findsOneWidget);
    await third.up();
    await fourth.up();
    await tester.pumpAndSettle();
    expect(fixture.commits.map((commit) => commit.$1), [2, 3]);
    expect(fixture.groups.layoutType, GalleryLayoutType.grid);
    expect(fixture.groups.crossAxisCount, 3);
    expect(_overlay, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets("clamps an enlarged short album to its new scroll extent", (
    tester,
  ) async {
    await localSettings.setPhotoGridSize(3);
    final fixture = _ZoomFixture(fileCount: 8, leadingExtent: 56);
    addTearDown(fixture.controller.dispose);
    await fixture.mount(tester);
    expect(fixture.controller.position.maxScrollExtent, 0);
    final source = fixture.groups.gridZoomLayout(
      columns: 3,
      headerExtent: GalleryGroups.spacing,
    );
    final target = fixture.groups.gridZoomLayout(
      columns: 2,
      headerExtent: GalleryGroups.spacing,
    );
    final sourceTile = source.tileForIndex(5)!;
    final focalPoint = Offset(
      sourceTile.rect.center.dx,
      fixture.leadingExtent +
          sourceTile.rect.top +
          sourceTile.rect.height * 0.75,
    );
    final expectedMaximum = fixture.leadingExtent + target.totalExtent - 600;
    expect(expectedMaximum, greaterThan(0));
    final first = await tester.startGesture(
      focalPoint - const Offset(50, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      focalPoint + const Offset(50, 0),
      pointer: 2,
    );
    await first.moveTo(focalPoint - const Offset(150, 0));
    await second.moveTo(focalPoint + const Offset(150, 0));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(fixture.commits.single.$1, 2);
    expect(fixture.commits.single.$2, closeTo(expectedMaximum, 0.001));
    expect(fixture.controller.offset, closeTo(expectedMaximum, 0.001));
    expect(_overlay, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets("a file refresh invalidates an overlay while commit is pending", (
    tester,
  ) async {
    final fixture = _ZoomFixture()..commitGate = Completer<void>();
    addTearDown(fixture.controller.dispose);
    await fixture.mount(tester);
    fixture.controller.jumpTo(700);
    await tester.pump();
    final first = await tester.startGesture(const Offset(170, 280), pointer: 1);
    final second = await tester.startGesture(
      const Offset(330, 280),
      pointer: 2,
    );
    await first.moveTo(const Offset(186, 280));
    await second.moveTo(const Offset(314, 280));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(fixture.commits, hasLength(1));
    expect(_overlay, findsOneWidget);

    fixture.rebuild(() {
      fixture.files = fixture.files.skip(1).toList();
      fixture.groups = fixture._groups();
    });
    await tester.pump();
    expect(_overlay, findsNothing);
    fixture.commitGate!.complete();
    await tester.pumpAndSettle();
    expect(_overlay, findsNothing);
    expect(fixture.commits, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    "a cold pinch remembers justified when released before preparation",
    (tester) async {
      await localSettings.setPhotoGridSize(3);
      final fixture = _ZoomFixture();
      addTearDown(fixture.controller.dispose);
      await fixture.mount(tester, prewarm: false);
      final sourceGroups = fixture.groups;
      late Future<void> prepared;
      await tester.runAsync(() async {
        prepared = sourceGroups
            .prepareJustifiedZoomLayout(headerExtent: GalleryGroups.spacing)
            .then((_) {});
      });
      expect(
        sourceGroups.cachedGridZoomLayout(
          columns: 2,
          headerExtent: GalleryGroups.spacing,
        ),
        isNull,
      );
      fixture.controller.jumpTo(700);
      await tester.pump();
      final first = await tester.startGesture(
        const Offset(200, 280),
        pointer: 1,
      );
      final second = await tester.startGesture(
        const Offset(300, 280),
        pointer: 2,
      );
      await first.moveTo(const Offset(150, 280));
      await second.moveTo(const Offset(350, 280));
      await first.up();
      await second.up();
      expect(fixture.commits, isEmpty);
      expect(
        sourceGroups.cachedGridZoomLayout(
          columns: 2,
          headerExtent: GalleryGroups.spacing,
        ),
        isNull,
      );
      await tester.runAsync(() => prepared);
      await tester.pumpAndSettle();
      expect(fixture.commits, hasLength(1));
      expect(fixture.commits.single.$1, 2);
      expect(fixture.groups.layoutType, GalleryLayoutType.justified);
      expect(_overlay, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets("cold geometry catches up continuously during an active pinch", (
    tester,
  ) async {
    await localSettings.setPhotoGridSize(3);
    final fixture = _ZoomFixture();
    addTearDown(fixture.controller.dispose);
    await fixture.mount(tester, prewarm: false);
    final sourceGroups = fixture.groups;
    late Future<void> prepared;
    await tester.runAsync(() async {
      prepared = sourceGroups
          .prepareJustifiedZoomLayout(headerExtent: GalleryGroups.spacing)
          .then((_) {});
    });
    const anchorIndex = 31;
    const focalY = 300.0;
    final sourceTile = sourceGroups
        .gridZoomLayout(columns: 3, headerExtent: GalleryGroups.spacing)
        .tileForIndex(anchorIndex)!;
    fixture.controller.jumpTo(
      _ZoomFixture.contentTop + sourceTile.rect.center.dy - focalY,
    );
    await tester.pump();
    final focalX = sourceTile.rect.center.dx;
    final first = await tester.startGesture(
      Offset(focalX - 50, focalY),
      pointer: 1,
    );
    final second = await tester.startGesture(
      Offset(focalX + 50, focalY),
      pointer: 2,
    );
    await first.moveTo(Offset(focalX - 150, focalY));
    await second.moveTo(Offset(focalX + 150, focalY));
    await tester.pump();
    final tileFinder = find.byKey(
      const ValueKey(("gallery-grid-zoom-tile", anchorIndex)),
    );
    final heldRect = tester.getRect(tileFinder);
    expect(heldRect.size, sourceTile.rect.size);
    expect(
      sourceGroups.cachedGridZoomLayout(
        columns: 2,
        headerExtent: GalleryGroups.spacing,
      ),
      isNull,
    );

    await tester.runAsync(() => prepared);
    await tester.pump();
    expect(tester.getRect(tileFinder), heldRect);
    final targetTile = sourceGroups
        .gridZoomLayout(columns: 2, headerExtent: GalleryGroups.spacing)
        .tileForIndex(anchorIndex)!;
    await tester.pump(const Duration(milliseconds: 45));
    final intermediate = tester.getRect(tileFinder);
    final progress =
        (intermediate.height - heldRect.height) /
        (targetTile.rect.height - heldRect.height);
    expect(progress, greaterThan(0));
    expect(progress, lessThan(1));
    expect(intermediate.center.dy, closeTo(focalY, 0.001));
    expect(fixture.commits, isEmpty);
    await tester.pump(const Duration(milliseconds: 45));
    expect(tester.getRect(tileFinder).size, targetTile.rect.size);
    expect(fixture.commits, isEmpty);
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(fixture.commits, hasLength(1));
    expect(fixture.commits.single.$1, 2);
    expect(_overlay, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Finder get _overlay => find.byKey(const ValueKey("gallery-grid-zoom-overlay"));

class _ZoomFixture {
  _ZoomFixture({
    int fileCount = 1200,
    this.leadingExtent = contentTop,
    this.groupType = GroupType.none,
    this.selectedFiles,
  }) : files = List<EnteFile>.generate(
         fileCount,
         (index) => EnteFile()
           ..generatedID = index + 1
           ..creationTime = DateTime(2026, 8, 19).microsecondsSinceEpoch
           ..fileType = FileType.image
           ..pubMagicMetadata = PubMagicMetadata(
             w: index.isEven ? 1600 : 900,
             h: index.isEven ? 900 : 1600,
           ),
       );

  static const contentTop = 112.0;
  final double leadingExtent;
  final GroupType groupType;
  final SelectedFiles? selectedFiles;
  double get headerExtent =>
      groupType == GroupType.none ? GalleryGroups.spacing : 48;
  final controller = ScrollController();
  final commits = <(int, double)>[];
  List<EnteFile> files;
  Completer<void>? commitGate;
  late GalleryGroups groups;
  late StateSetter rebuild;

  GalleryGroups _groups() => GalleryGroups(
    allFiles: files,
    groupType: groupType,
    widthAvailable: 400,
    selectedFiles: selectedFiles,
    tagPrefix: "zoom_test_",
    groupHeaderExtent: headerExtent,
    showSelectAll: selectedFiles != null,
  );

  Future<void> mount(WidgetTester tester, {bool prewarm = true}) async {
    groups = _groups();
    if (prewarm) {
      await tester.runAsync(
        () => groups.prepareJustifiedZoomLayout(headerExtent: headerExtent),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 600,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return GalleryGridZoom(
                  groups: groups,
                  scrollController: controller,
                  sectionOrigin: () => leadingExtent - controller.offset,
                  appBarHeight: 56,
                  pinHeaders: false,
                  showSelectAll: selectedFiles != null,
                  enabled: true,
                  onCommit: (columns, scrollOffset) async {
                    commits.add((columns, scrollOffset));
                    await commitGate?.future;
                    await localSettings.setGalleryLayoutType(
                      columns == 2
                          ? GalleryLayoutType.justified
                          : GalleryLayoutType.grid,
                    );
                    if (columns != 2) {
                      await localSettings.setPhotoGridSize(columns);
                    }
                    rebuild(() => groups = _groups());
                    await WidgetsBinding.instance.endOfFrame;
                    controller.jumpTo(scrollOffset);
                  },
                  thumbnailBuilder: (_) => const ColoredBox(color: Colors.blue),
                  child: SingleChildScrollView(
                    key: const ValueKey("gallery-scroll"),
                    controller: controller,
                    child: SizedBox(
                      height:
                          leadingExtent + groups.groupLayouts.last.maxOffset,
                      child: const ColoredBox(color: Colors.black),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}
