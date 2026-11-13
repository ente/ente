import "dart:collection";

import "package:dio/dio.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/gallery/fixed_extent_section_layout.dart";
import "package:photos/models/gallery/gallery_grid_zoom_layout.dart";
import "package:photos/models/gallery/gallery_groups.dart";
import "package:photos/models/gallery/justified_layout.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
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
    try {
      await Configuration.instance.init(preferences);
    } catch (_) {}
    await localSettings.setGalleryLayoutType(GalleryLayoutType.grid);
  });

  test(
    "previews match settled rows, padding and headers at both densities",
    () async {
      final files = <EnteFile>[];
      for (final (day, count) in [(14, 5), (13, 61), (12, 2), (11, 7)]) {
        for (var index = 0; index < count; index++) {
          files.add(_file(files.length, day: day));
        }
      }
      final source = _groups(files, GroupType.day, 48);
      final headerIDs = <List<String>>[];
      for (final columns in [3, 6]) {
        final headerExtent = columns == 6 ? 52.0 : 48.0;
        final preview = source.gridZoomLayout(
          columns: columns,
          headerExtent: headerExtent,
        );
        await localSettings.setPhotoGridSize(columns);
        final settled = _groups(files, GroupType.day, headerExtent);
        _expectMatchesSettled(preview, settled);
        final headers = preview.headersInViewport(
          Rect.fromLTWH(0, 0, preview.width, preview.totalExtent),
        );
        headerIDs.add(headers.map((header) => header.id).toList());
        expect(headers.map((header) => header.firstFile), [
          files[0],
          files[5],
          files[66],
          files[68],
        ]);
        for (final header in headers) {
          expect(preview.headerAtOffset(header.rect.top)!.id, header.id);
          expect(preview.tileAt(header.rect.center), isNull);
        }
        expect(
          preview.tilesInViewport(
            Rect.fromLTWH(0, 0, preview.width, preview.totalExtent),
          ),
          hasLength(files.length),
        );
      }
      expect(headerIDs.first, headerIDs.last);
    },
  );

  test("ungrouped previews match density-dependent chunk boundaries", () async {
    final files = List.generate(127, _file);
    final source = _groups(files, GroupType.none, GalleryGroups.spacing);
    for (final columns in [3, 6]) {
      final preview = source.gridZoomLayout(
        columns: columns,
        headerExtent: GalleryGroups.spacing,
      );
      await localSettings.setPhotoGridSize(columns);
      final settled = _groups(files, GroupType.none, GalleryGroups.spacing);
      _expectMatchesSettled(preview, settled);
      expect(preview.headerAtOffset(preview.totalExtent / 2), isNull);
      expect(
        preview.headersInViewport(
          Rect.fromLTWH(0, 0, preview.width, preview.totalExtent),
        ),
        isEmpty,
      );
    }
  });

  test("focal lookups reject gaps and dummies and preserve file identity", () {
    final files = List.generate(5, _file);
    final groups = _groups(files, GroupType.day, 48);
    for (final columns in [3, 6]) {
      final layout = groups.gridZoomLayout(columns: columns, headerExtent: 48);
      for (var index = 0; index < files.length; index++) {
        final tile = layout.tileForIndex(index)!;
        final focalPoint =
            tile.rect.topLeft +
            Offset(tile.rect.width * 0.27, tile.rect.height * 0.73);
        expect(layout.tileAt(focalPoint)!.index, index);
        expect(layout.tileAt(focalPoint)!.file, same(files[index]));
      }
      final firstTile = layout.tileForIndex(0)!;
      expect(
        layout.tileAt(
          Offset(firstTile.rect.right + 0.5, firstTile.rect.center.dy),
        ),
        isNull,
      );
      final lastTile = layout.tileForIndex(files.length - 1)!;
      expect(
        layout.tileAt(
          Offset(layout.width - layout.tileExtent / 2, lastTile.rect.center.dy),
        ),
        isNull,
      );
      expect(layout.tileAt(Offset(-1, firstTile.rect.center.dy)), isNull);
      expect(layout.tileAt(Offset(1, layout.totalExtent)), isNull);
      expect(layout.tileForIndex(files.length), isNull);
    }
    final empty = _groups(
      [],
      GroupType.none,
      GalleryGroups.spacing,
    ).gridZoomLayout(columns: 3, headerExtent: GalleryGroups.spacing);
    expect(empty.totalExtent, 0);
    expect(empty.tileAt(Offset.zero), isNull);
    expect(empty.tilesInViewport(const Rect.fromLTWH(0, 0, 390, 800)), isEmpty);
  });

  test(
    "Justified endpoints reuse production rows and retain header identity",
    () async {
      final files = _CountingFiles(
        List.generate(79, (index) {
          final (width, height) = switch (index % 3) {
            0 => (400, 100),
            1 => (100, 400),
            _ => (200, 200),
          };
          return _file(index, day: 14 - index ~/ 27)
            ..pubMagicMetadata = PubMagicMetadata(w: width, h: height);
        }),
      );
      for (final grouping in [GroupType.day, GroupType.none]) {
        final headerExtent = grouping == GroupType.none
            ? GalleryGroups.spacing
            : 48.0;
        final square = _groups(files, grouping, headerExtent);
        final justified = _groups(
          files,
          grouping,
          headerExtent,
          layoutType: GalleryLayoutType.justified,
        );
        expect(
          square.cachedGridZoomLayout(columns: 2, headerExtent: headerExtent),
          isNull,
        );
        final preparation = square.prepareJustifiedZoomLayout(
          headerExtent: headerExtent,
        );
        expect(
          square.prepareJustifiedZoomLayout(headerExtent: headerExtent),
          same(preparation),
        );
        final fromSquare = await preparation;
        _expectMatchesJustified(fromSquare, justified);
        for (final file in files.cast<_DimensionCountingFile>()) {
          file.dimensionReads = 0;
        }
        final committed = _groups(
          files,
          grouping,
          headerExtent,
          layoutType: GalleryLayoutType.justified,
          reuseLayoutFrom: square,
        );
        expect(
          files.cast<_DimensionCountingFile>().every(
            (file) => file.dimensionReads == 0,
          ),
          isTrue,
        );
        _expectMatchesJustified(fromSquare, committed);
        final nextSquare = _groups(
          files,
          grouping,
          headerExtent,
          reuseLayoutFrom: committed,
        );
        expect(
          nextSquare.cachedGridZoomLayout(
            columns: 2,
            headerExtent: headerExtent,
          ),
          isNotNull,
        );
        final nextJustified = _groups(
          files,
          grouping,
          headerExtent,
          layoutType: GalleryLayoutType.justified,
          reuseLayoutFrom: nextSquare,
        );
        for (var index = 0; index < committed.groupLayouts.length; index++) {
          expect(
            (nextJustified.groupLayouts[index] as JustifiedSectionLayout).rows,
            same(
              (committed.groupLayouts[index] as JustifiedSectionLayout).rows,
            ),
          );
        }
        files.readCount = 0;
        expect(
          square.cachedGridZoomLayout(columns: 2, headerExtent: headerExtent),
          same(fromSquare),
        );
        expect(files.readCount, 0);
        final fromJustified = justified.cachedGridZoomLayout(
          columns: 2,
          headerExtent: headerExtent,
        )!;
        expect(files.readCount, 0);
        _expectMatchesJustified(fromJustified, justified);
        final squareEndpoint = justified.gridZoomLayout(
          columns: 3,
          headerExtent: headerExtent,
        );
        final allHeaders = Rect.fromLTWH(
          0,
          0,
          390,
          fromJustified.totalExtent + squareEndpoint.totalExtent,
        );
        expect(
          fromJustified
              .headersInViewport(allHeaders)
              .map((header) => header.id),
          squareEndpoint
              .headersInViewport(allHeaders)
              .map((header) => header.id),
        );
      }
    },
  );

  test("deep viewport enumeration reads only intersecting tiles", () async {
    final files = _CountingFiles(List.generate(60000, _file));
    final groups = _groups(files, GroupType.none, GalleryGroups.spacing);
    for (final columns in [2, 6]) {
      final layout = columns == 2
          ? await groups.prepareJustifiedZoomLayout(
              headerExtent: GalleryGroups.spacing,
            )
          : groups.gridZoomLayout(
              columns: columns,
              headerExtent: GalleryGroups.spacing,
            );
      final viewport = Rect.fromLTWH(0, layout.totalExtent * 0.8, 390, 800);
      files.readCount = 0;
      final tiles = layout.tilesInViewport(viewport);
      expect(tiles, isNotEmpty);
      expect(tiles.first.index, greaterThan(45000));
      expect(tiles, hasLength(lessThan(100)));
      expect(tiles.every((tile) => tile.rect.overlaps(viewport)), isTrue);
      expect(files.readCount, lessThan(200));
      files.readCount = 0;
      expect(layout.tileForIndex(tiles.first.index)!.rect, tiles.first.rect);
      expect(files.readCount, lessThan(4));
    }
  });
}

void _expectMatchesJustified(
  GalleryGridZoomLayout preview,
  GalleryGroups settled,
) {
  expect(
    preview.totalExtent,
    closeTo(settled.groupLayouts.last.maxOffset, 1e-8),
  );
  var rawIndex = 0;
  for (
    var groupIndex = 0;
    groupIndex < settled.groupLayouts.length;
    groupIndex++
  ) {
    final section = settled.groupLayouts[groupIndex] as JustifiedSectionLayout;
    final files = settled.groupIDToFilesMap[settled.groupIDs[groupIndex]]!;
    for (final row in section.rows) {
      var left = 0.0;
      for (var column = 0; column < row.itemWidths.length; column++) {
        final tile = preview.tileForIndex(rawIndex++)!;
        expect(tile.file, same(files[row.firstIndex + column]));
        expect(tile.rect.left, closeTo(left, 1e-8));
        expect(
          tile.rect.top,
          closeTo(section.bodyMinOffset + row.minOffset, 1e-8),
        );
        expect(tile.rect.width, closeTo(row.itemWidths[column], 1e-8));
        expect(tile.rect.height, closeTo(row.height, 1e-8));
        expect(preview.tileAt(tile.rect.center)!.index, tile.index);
        left += row.itemWidths[column] + GalleryGroups.spacing;
      }
    }
  }
  expect(
    preview
        .tilesInViewport(Rect.fromLTWH(0, 0, 390, preview.totalExtent))
        .map((tile) => tile.index),
    orderedEquals(List.generate(rawIndex, (index) => index)),
  );
}

void _expectMatchesSettled(
  GalleryGridZoomLayout preview,
  GalleryGroups settled,
) {
  expect(
    preview.totalExtent,
    closeTo(settled.groupLayouts.last.maxOffset, 1e-8),
  );
  var rawIndex = 0;
  for (
    var groupIndex = 0;
    groupIndex < settled.groupLayouts.length;
    groupIndex++
  ) {
    final section =
        settled.groupLayouts[groupIndex] as FixedExtentSectionLayout;
    final files = settled.groupIDToFilesMap[settled.groupIDs[groupIndex]]!;
    for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
      if (files[fileIndex] is DummyFile) continue;
      final tile = preview.tileForIndex(rawIndex++)!;
      expect(tile.file, same(files[fileIndex]));
      expect(
        tile.rect.left,
        closeTo((fileIndex % preview.columns) * section.mainAxisStride, 1e-8),
      );
      expect(
        tile.rect.top,
        closeTo(
          section.bodyMinOffset +
              (fileIndex ~/ preview.columns) * section.mainAxisStride,
          1e-8,
        ),
      );
      expect(tile.rect.width, closeTo(section.tileHeight, 1e-8));
      expect(tile.rect.height, closeTo(section.tileHeight, 1e-8));
    }
  }
}

GalleryGroups _groups(
  List<EnteFile> files,
  GroupType groupType,
  double headerExtent, {
  GalleryLayoutType layoutType = GalleryLayoutType.grid,
  GalleryGroups? reuseLayoutFrom,
}) => GalleryGroups(
  allFiles: files,
  groupType: groupType,
  sortOrderAsc: false,
  widthAvailable: 390,
  selectedFiles: null,
  tagPrefix: "zoom_test_",
  groupHeaderExtent: headerExtent,
  showSelectAll: false,
  layoutTypeOverride: layoutType,
  reuseLayoutFrom: reuseLayoutFrom,
);

EnteFile _file(int index, {int day = 14}) => _DimensionCountingFile()
  ..generatedID = index + 1
  ..creationTime = DateTime(2026, 10, day).microsecondsSinceEpoch
  ..fileType = FileType.image;

class _DimensionCountingFile extends EnteFile {
  var dimensionReads = 0;

  @override
  int get width {
    dimensionReads++;
    return super.width;
  }

  @override
  int get height {
    dimensionReads++;
    return super.height;
  }
}

class _CountingFiles extends ListBase<EnteFile> {
  _CountingFiles(this.files);

  final List<EnteFile> files;
  var readCount = 0;

  @override
  int get length => files.length;

  @override
  set length(int value) => files.length = value;

  @override
  EnteFile operator [](int index) {
    readCount++;
    return files[index];
  }

  @override
  void operator []=(int index, EnteFile file) => files[index] = file;
}
