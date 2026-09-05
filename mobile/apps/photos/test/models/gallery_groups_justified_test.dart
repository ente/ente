import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:logging/logging.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/gallery/fixed_extent_section_layout.dart";
import "package:photos/models/gallery/gallery_groups.dart";
import "package:photos/models/gallery/justified_grid_row.dart";
import "package:photos/models/gallery/justified_layout.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/viewer/gallery/component/gallery_file_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
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

    // GalleryGroups only reads Configuration's preferences-backed user ID.
    // The remaining plugin initialization is unavailable in unit tests.
    try {
      await Configuration.instance.init(preferences);
    } catch (_) {}
  });

  setUp(() async {
    await localSettings.setGalleryLayoutType(GalleryLayoutType.justified);
    await localSettings.setPhotoGridSize(4);
  });

  test("day grouping creates independent, contiguous justified sections", () {
    for (final sortOrderAsc in [false, true]) {
      final days = sortOrderAsc ? [17, 18, 19] : [19, 18, 17];
      final expectedGroups = <List<EnteFile>>[];
      final files = <EnteFile>[];
      var fileIndex = 0;
      for (final day in days) {
        final filesForDay = List<EnteFile>.generate(5, (index) {
          final isPortrait = index.isEven;
          return _file(
            index: fileIndex++,
            creationTime: DateTime(2026, 8, day).microsecondsSinceEpoch,
            width: isPortrait ? 100 : 400,
            height: isPortrait ? 400 : 100,
          );
        }, growable: false);
        expectedGroups.add(filesForDay);
        files.addAll(filesForDay);
      }

      final groups = _galleryGroups(
        files: files,
        groupType: GroupType.day,
        groupHeaderExtent: 48,
        sortOrderAsc: sortOrderAsc,
      );

      expect(groups.groupIDs, hasLength(expectedGroups.length));
      expect(groups.groupLayouts, hasLength(expectedGroups.length));
      var expectedFirstChildIndex = 0;
      var expectedSectionOffset = 0.0;

      for (
        var groupIndex = 0;
        groupIndex < expectedGroups.length;
        groupIndex++
      ) {
        final expectedFiles = expectedGroups[groupIndex];
        final groupID = groups.groupIDs[groupIndex];
        final section = groups.groupLayouts[groupIndex];

        expect(section, isA<JustifiedSectionLayout>());
        final justifiedSection = section as JustifiedSectionLayout;
        expect(groups.groupIDToFilesMap[groupID], orderedEquals(expectedFiles));
        expect(justifiedSection.firstIndex, expectedFirstChildIndex);
        expect(
          justifiedSection.minOffset,
          closeTo(expectedSectionOffset, 1e-9),
        );
        expect(justifiedSection.headerExtent, 48);
        _expectRowsCoverFiles(justifiedSection, expectedFiles.length);
        expect(
          groups.getFileAtScrollOffset(justifiedSection.minOffset),
          same(expectedFiles.first),
          reason: "a shared section boundary belongs to the next section",
        );
        if (groupIndex > 0) {
          expect(
            groups.groupLayouts[groupIndex - 1].maxOffset,
            justifiedSection.minOffset,
          );
        }

        for (final file in expectedFiles) {
          final fileOffset = groups.getOffsetOfFile(file);
          expect(fileOffset, isNotNull);
          expect(groups.getFileAtScrollOffset(fileOffset!), same(file));
          expect(
            groups.getOffsetOfGroupContainingFile(file),
            closeTo(justifiedSection.minOffset, 1e-9),
          );
        }

        expectedFirstChildIndex = justifiedSection.lastIndex + 1;
        expectedSectionOffset = justifiedSection.maxOffset;
      }
    }
  });

  test(
    "headerless justified remains one continuous group past grid chunks",
    () {
      const fileCount = 100;
      final files = List<EnteFile>.generate(
        fileCount,
        (index) => _file(
          index: index,
          creationTime: DateTime(2026, 8, 19).microsecondsSinceEpoch,
          width: 3,
          height: 2,
        ),
        growable: false,
      );

      final groups = _galleryGroups(
        files: files,
        groupType: GroupType.none,
        groupHeaderExtent: GalleryGroups.spacing,
      );

      expect(groups.groupIDs, hasLength(1));
      expect(groups.groupLayouts, hasLength(1));
      expect(groups.groupIDToFilesMap.values.single, orderedEquals(files));
      expect(groups.allFilesWithDummies, hasLength(fileCount));
      for (var index = 0; index < fileCount; index++) {
        expect(groups.allFilesWithDummies[index], same(files[index]));
        expect(groups.allFilesWithDummies[index], isNot(isA<DummyFile>()));
      }

      final section = groups.groupLayouts.single as JustifiedSectionLayout;
      expect(section.headerExtent, GalleryGroups.spacing);
      expect(section.bodyMinOffset, GalleryGroups.spacing);
      _expectRowsCoverFiles(section, fileCount);

      final rowAcrossLegacyBoundary = section.rows.singleWhere(
        (row) => row.firstIndex <= 39 && row.lastIndex >= 40,
      );
      expect(rowAcrossLegacyBoundary.firstIndex, 39);
      expect(rowAcrossLegacyBoundary.lastIndex, 41);

      for (final row in section.rows) {
        final firstFileInRow = files[row.firstIndex];
        final fileOffset = groups.getOffsetOfFile(firstFileInRow);
        expect(fileOffset, isNotNull);
        expect(groups.getFileAtScrollOffset(fileOffset!), same(firstFileInRow));
      }
      expect(
        groups.getFileAtScrollOffset(section.maxOffset),
        same(files[section.rows.last.firstIndex]),
      );
    },
  );

  test(
    "caps the target height only when the grid-derived target is taller",
    () async {
      final file = _file(
        index: 0,
        creationTime: DateTime(2026, 8, 19).microsecondsSinceEpoch,
        width: 1,
        height: 1,
      );
      double rowHeight() {
        final section =
            _galleryGroups(
                  files: [file],
                  groupType: GroupType.none,
                  groupHeaderExtent: GalleryGroups.spacing,
                  widthAvailable: 1024,
                ).groupLayouts.single
                as JustifiedSectionLayout;
        return section.rows.single.height;
      }

      await localSettings.setPhotoGridSize(2);
      expect(rowHeight(), 320);

      await localSettings.setPhotoGridSize(4);
      expect(rowHeight(), (1024 - 3 * GalleryGroups.spacing) / 4);
    },
  );

  testWidgets("justified rows request large thumbnails for every tile", (
    tester,
  ) async {
    final files = List<EnteFile>.generate(
      2,
      (index) => _file(
        index: index,
        creationTime: DateTime(2026, 8, 19).microsecondsSinceEpoch,
        width: index.isEven ? 1 : 4,
        height: 1,
      ),
      growable: false,
    );
    final groups = _galleryGroups(
      files: files,
      groupType: GroupType.none,
      groupHeaderExtent: GalleryGroups.spacing,
    );
    final section = groups.groupLayouts.single as JustifiedSectionLayout;

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(key: ValueKey("justified-builder-context")),
      ),
    );
    final context = tester.element(
      find.byKey(const ValueKey("justified-builder-context")),
    );
    final rowWidget =
        section.builder(context, section.bodyFirstIndex) as JustifiedGridRow;
    final galleryTiles = rowWidget.children.map(
      (child) => (child as RepaintBoundary).child! as GalleryFileWidget,
    );

    expect(galleryTiles, hasLength(files.length));
    expect(
      galleryTiles.map((tile) => tile.thumbnailSize),
      everyElement(thumbnailLargeSize),
    );
  });

  test("malformed dimensions fall back to a square and log once", () async {
    final logs = <LogRecord>[];
    final subscription = Logger("File").onRecord.listen(logs.add);
    try {
      final file = EnteFile()
        ..generatedID = 1
        ..creationTime = DateTime(2026, 8, 19).microsecondsSinceEpoch
        ..fileType = FileType.image
        ..pubMmdEncodedJson = '{"w": 100';

      final groups = _galleryGroups(
        files: [file],
        groupType: GroupType.none,
        groupHeaderExtent: GalleryGroups.spacing,
      );
      final section = groups.groupLayouts.single as JustifiedSectionLayout;
      final row = section.rows.single;

      expect(row.itemWidths.single, row.height);
      expect(
        logs.where(
          (record) =>
              record.level == Level.SEVERE &&
              record.message.contains(
                "Failed to decode public metadata dimensions",
              ),
        ),
        hasLength(1),
      );
    } finally {
      await subscription.cancel();
    }
  });

  test("file geometry survives replacement with the same stable identity", () {
    final files = List<EnteFile>.generate(
      20,
      (index) => _file(
        index: index,
        creationTime: DateTime(2026, 8, 19).microsecondsSinceEpoch,
        width: 3,
        height: 2,
      ),
      growable: false,
    );
    final original = files[13]..localID = "local-13";
    final groups = _galleryGroups(
      files: files,
      groupType: GroupType.none,
      groupHeaderExtent: GalleryGroups.spacing,
    );
    final originalGeometry = groups.getGeometryOfFile(original);

    final replacement = EnteFile.from(original)..uploadedFileID = 1013;
    expect(replacement, isNot(same(original)));
    expect(replacement == original, isFalse);
    expect(groups.getGeometryOfFile(replacement), originalGeometry);
    expect(groups.getOffsetOfFile(replacement), originalGeometry?.rowOffset);
  });

  test("a layout override keeps an embedded gallery on the fixed grid", () {
    final files = List<EnteFile>.generate(
      12,
      (index) => _file(
        index: index,
        creationTime: DateTime(2026, 8, 19).microsecondsSinceEpoch,
        width: 400,
        height: 100,
      ),
      growable: false,
    );

    final groups = _galleryGroups(
      files: files,
      groupType: GroupType.none,
      groupHeaderExtent: GalleryGroups.spacing,
      layoutTypeOverride: GalleryLayoutType.grid,
    );

    expect(groups.layoutType, GalleryLayoutType.grid);
    expect(groups.groupLayouts, everyElement(isA<FixedExtentSectionLayout>()));
  });
}

GalleryGroups _galleryGroups({
  required List<EnteFile> files,
  required GroupType groupType,
  required double groupHeaderExtent,
  double widthAvailable = 430,
  bool sortOrderAsc = false,
  GalleryLayoutType? layoutTypeOverride,
}) {
  return GalleryGroups(
    allFiles: files,
    groupType: groupType,
    sortOrderAsc: sortOrderAsc,
    widthAvailable: widthAvailable,
    selectedFiles: null,
    tagPrefix: "test_",
    groupHeaderExtent: groupHeaderExtent,
    showSelectAll: false,
    layoutTypeOverride: layoutTypeOverride,
    justifiedLayoutAvailable: true,
  );
}

EnteFile _file({
  required int index,
  required int creationTime,
  required int width,
  required int height,
}) {
  return EnteFile()
    ..generatedID = index + 1
    ..creationTime = creationTime
    ..fileType = FileType.image
    ..pubMagicMetadata = PubMagicMetadata(w: width, h: height);
}

void _expectRowsCoverFiles(JustifiedSectionLayout section, int fileCount) {
  expect(section.rows, isNotEmpty);
  var expectedFirstFileIndex = 0;
  var expectedRowOffset = 0.0;
  for (final row in section.rows) {
    expect(row.firstIndex, expectedFirstFileIndex);
    expect(row.lastIndex, greaterThanOrEqualTo(row.firstIndex));
    expect(row.itemWidths, hasLength(row.lastIndex - row.firstIndex + 1));
    expect(row.minOffset, closeTo(expectedRowOffset, 1e-9));
    expectedFirstFileIndex = row.lastIndex + 1;
    expectedRowOffset = row.maxOffset + GalleryGroups.spacing;
  }
  expect(expectedFirstFileIndex, fileCount);
  expect(section.rows.last.lastIndex, fileCount - 1);
}
