import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/gallery/justified_layout.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";

class GalleryGridZoomTile {
  const GalleryGridZoomTile({
    required this.file,
    required this.index,
    required this.rect,
  });

  final EnteFile file;
  final int index;
  final Rect rect;
}

class GalleryGridZoomHeader {
  const GalleryGridZoomHeader({
    required this.id,
    required this.firstFile,
    required this.firstFileIndex,
    required this.endFileIndex,
    required this.groupType,
    required this.rect,
  });

  final String id;
  final EnteFile firstFile;
  final int firstFileIndex;
  final int endFileIndex;
  final GroupType groupType;
  final Rect rect;

  String title(BuildContext context) => groupType.getTitle(context, firstFile);
}

class GalleryGridZoomLayout {
  GalleryGridZoomLayout({
    required List<EnteFile> files,
    required List<int> groupEndIndexes,
    required this.groupType,
    required this.width,
    required this.columns,
    required this.headerExtent,
    required this.spacing,
    List<List<JustifiedRowLayout>>? justifiedRows,
  }) : _files = files,
       tileExtent = (width - (columns - 1) * spacing) / columns {
    var start = 0;
    var offset = 0.0;
    void addSection(int end) {
      final rows = columns == 2 ? justifiedRows![_sections.length] : null;
      final squareRowCount = (end - start + columns - 1) ~/ columns;
      final bodyExtent =
          rows?.last.maxOffset ??
          squareRowCount * tileExtent + (squareRowCount - 1) * spacing;
      final bottom = offset + headerExtent + bodyExtent;
      _sections.add(
        _GridZoomSection(
          firstFileIndex: start,
          endFileIndex: end,
          top: offset,
          rows: rows,
        ),
      );
      start = end;
      offset = bottom;
    }

    if (groupType.showGroupHeader()) {
      for (final end in groupEndIndexes) {
        addSection(end);
      }
    } else if (columns == 2) {
      if (files.isNotEmpty) addSection(files.length);
    } else {
      while (start < files.length) {
        addSection(math.min(start + 10 * columns, files.length));
      }
    }
    totalExtent = offset;
  }

  final List<EnteFile> _files;
  final List<_GridZoomSection> _sections = [];
  final GroupType groupType;
  final double width;
  final int columns;
  final double headerExtent;
  final double spacing;
  final double tileExtent;
  late final double totalExtent;

  double get _stride => tileExtent + spacing;

  GalleryGridZoomTile? tileAt(Offset position) {
    if (_sections.isEmpty ||
        !position.dx.isFinite ||
        !position.dy.isFinite ||
        position.dx < 0 ||
        position.dx >= width ||
        position.dy < 0 ||
        position.dy >= totalExtent) {
      return null;
    }
    final section = _sections[_sectionIndexAt(position.dy)];
    final rowOffset = position.dy - section.top - headerExtent;
    if (rowOffset < 0) return null;
    final justifiedRows = section.rows;
    if (justifiedRows != null) {
      final row = justifiedRows[_rowIndexAt(justifiedRows, rowOffset)];
      for (
        var fileIndex = row.firstIndex;
        fileIndex <= row.lastIndex;
        fileIndex++
      ) {
        final tile = _justifiedTile(section, row, fileIndex);
        if (tile.rect.contains(position) && tile.file is! DummyFile) {
          return tile;
        }
      }
      return null;
    }
    final row = (rowOffset / _stride).floor();
    final column = (position.dx / _stride).floor();
    final fileIndex = section.firstFileIndex + row * columns + column;
    if (fileIndex >= section.endFileIndex) return null;
    final tile = _tile(section, fileIndex);
    return tile.rect.contains(position) && tile.file is! DummyFile
        ? tile
        : null;
  }

  List<GalleryGridZoomTile> tilesInViewport(Rect viewport) {
    final tiles = <GalleryGridZoomTile>[];
    if (_sections.isEmpty ||
        viewport.isEmpty ||
        !viewport.overlaps(Rect.fromLTWH(0, 0, width, totalExtent))) {
      return tiles;
    }
    final firstColumn = (viewport.left / _stride).floor().clamp(0, columns - 1);
    final lastColumn = (viewport.right / _stride).floor().clamp(0, columns - 1);
    for (
      var index = _sectionIndexAt(viewport.top);
      index < _sections.length && _sections[index].top < viewport.bottom;
      index++
    ) {
      final section = _sections[index];
      final bodyTop = section.top + headerExtent;
      final justifiedRows = section.rows;
      if (justifiedRows != null) {
        final firstRow = _rowIndexAt(justifiedRows, viewport.top - bodyTop);
        final lastRow = _rowIndexAt(justifiedRows, viewport.bottom - bodyTop);
        for (var rowIndex = firstRow; rowIndex <= lastRow; rowIndex++) {
          final row = justifiedRows[rowIndex];
          for (
            var fileIndex = row.firstIndex;
            fileIndex <= row.lastIndex;
            fileIndex++
          ) {
            final tile = _justifiedTile(section, row, fileIndex);
            if (tile.rect.overlaps(viewport) && tile.file is! DummyFile) {
              tiles.add(tile);
            }
          }
        }
        continue;
      }
      final rowCount =
          (section.endFileIndex - section.firstFileIndex + columns - 1) ~/
          columns;
      final firstRow = ((viewport.top - bodyTop) / _stride).floor().clamp(
        0,
        rowCount - 1,
      );
      final lastRow = ((viewport.bottom - bodyTop) / _stride).floor().clamp(
        0,
        rowCount - 1,
      );
      for (var row = firstRow; row <= lastRow; row++) {
        for (var column = firstColumn; column <= lastColumn; column++) {
          final fileIndex = section.firstFileIndex + row * columns + column;
          if (fileIndex >= section.endFileIndex) break;
          if (_files[fileIndex] is DummyFile) continue;
          final tile = _tile(section, fileIndex);
          if (tile.rect.overlaps(viewport)) tiles.add(tile);
        }
      }
    }
    return tiles;
  }

  List<GalleryGridZoomHeader> headersInViewport(Rect viewport) {
    final headers = <GalleryGridZoomHeader>[];
    if (!groupType.showGroupHeader() || _sections.isEmpty || viewport.isEmpty) {
      return headers;
    }
    for (
      var index = _sectionIndexAt(viewport.top);
      index < _sections.length && _sections[index].top < viewport.bottom;
      index++
    ) {
      final section = _sections[index];
      final rect = Rect.fromLTWH(0, section.top, width, headerExtent);
      if (rect.overlaps(viewport)) {
        headers.add(_header(section));
      }
    }
    return headers;
  }

  GalleryGridZoomHeader? headerAtOffset(double offset) {
    if (!groupType.showGroupHeader() ||
        _sections.isEmpty ||
        !offset.isFinite ||
        offset < 0 ||
        offset >= totalExtent) {
      return null;
    }
    return _header(_sections[_sectionIndexAt(offset)]);
  }

  GalleryGridZoomHeader _header(_GridZoomSection section) =>
      GalleryGridZoomHeader(
        id: "${groupType.name}:${section.firstFileIndex}",
        firstFile: _files[section.firstFileIndex],
        firstFileIndex: section.firstFileIndex,
        endFileIndex: section.endFileIndex,
        groupType: groupType,
        rect: Rect.fromLTWH(0, section.top, width, headerExtent),
      );

  GalleryGridZoomTile? tileForIndex(int fileIndex) {
    if (fileIndex < 0 ||
        fileIndex >= _files.length ||
        _files[fileIndex] is DummyFile) {
      return null;
    }
    var low = 0;
    var high = _sections.length - 1;
    while (low < high) {
      final middle = (low + high) >>> 1;
      if (fileIndex >= _sections[middle].endFileIndex) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return _tile(_sections[low], fileIndex);
  }

  GalleryGridZoomTile _tile(_GridZoomSection section, int fileIndex) {
    final indexInSection = fileIndex - section.firstFileIndex;
    final justifiedRows = section.rows;
    if (justifiedRows != null) {
      var low = 0;
      var high = justifiedRows.length - 1;
      while (low < high) {
        final middle = (low + high) >>> 1;
        if (indexInSection > justifiedRows[middle].lastIndex) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      return _justifiedTile(section, justifiedRows[low], indexInSection);
    }
    return GalleryGridZoomTile(
      file: _files[fileIndex],
      index: fileIndex,
      rect: Rect.fromLTWH(
        (indexInSection % columns) * _stride,
        section.top + headerExtent + (indexInSection ~/ columns) * _stride,
        tileExtent,
        tileExtent,
      ),
    );
  }

  GalleryGridZoomTile _justifiedTile(
    _GridZoomSection section,
    JustifiedRowLayout row,
    int indexInSection,
  ) {
    final column = indexInSection - row.firstIndex;
    var left = 0.0;
    for (var index = 0; index < column; index++) {
      left += row.itemWidths[index] + spacing;
    }
    final fileIndex = section.firstFileIndex + indexInSection;
    return GalleryGridZoomTile(
      file: _files[fileIndex],
      index: fileIndex,
      rect: Rect.fromLTWH(
        left,
        section.top + headerExtent + row.minOffset,
        row.itemWidths[column],
        row.height,
      ),
    );
  }

  int _rowIndexAt(List<JustifiedRowLayout> rows, double offset) {
    var low = 0;
    var high = rows.length - 1;
    var result = 0;
    while (low <= high) {
      final middle = (low + high) >>> 1;
      if (rows[middle].minOffset <= offset) {
        result = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return result;
  }

  int _sectionIndexAt(double offset) {
    var low = 0;
    var high = _sections.length - 1;
    var result = 0;
    while (low <= high) {
      final middle = (low + high) >>> 1;
      if (_sections[middle].top <= offset) {
        result = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return result;
  }
}

class _GridZoomSection {
  const _GridZoomSection({
    required this.firstFileIndex,
    required this.endFileIndex,
    required this.top,
    required this.rows,
  });

  final int firstFileIndex;
  final int endFileIndex;
  final double top;
  final List<JustifiedRowLayout>? rows;
}
