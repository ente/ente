import "dart:core";
import "dart:math" as math;

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/gallery/fixed_extent_grid_row.dart";
import "package:photos/models/gallery/fixed_extent_section_layout.dart";
import "package:photos/models/gallery/gallery_layout_config.dart";
import "package:photos/models/gallery/justified_grid_row.dart";
import "package:photos/models/gallery/justified_layout.dart";
import "package:photos/models/gallery/section_layout.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/viewer/gallery/component/dummy_file_widget.dart";
import "package:photos/ui/viewer/gallery/component/gallery_file_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/group_header_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:uuid/uuid.dart";

class GalleryGroups {
  final List<EnteFile> allFiles;
  final GroupType groupType;
  final SelectedFiles? selectedFiles;
  final bool limitSelectionToOne;
  final String tagPrefix;
  final bool showSelectAll;
  final _logger = Logger("GalleryGroups");
  final bool showGallerySettingsCTA;
  final GalleryLayoutType? layoutTypeOverride;
  final bool justifiedLayoutAvailable;

  final bool sortOrderAsc;
  final double widthAvailable;
  final double groupHeaderExtent;
  GalleryGroups({
    required this.allFiles,
    required this.groupType,
    required this.widthAvailable,
    required this.selectedFiles,
    required this.tagPrefix,
    this.sortOrderAsc = true,
    required this.groupHeaderExtent,
    required this.showSelectAll,
    this.limitSelectionToOne = false,
    this.showGallerySettingsCTA = false,
    this.layoutTypeOverride,
    required this.justifiedLayoutAvailable,
  }) {
    init();
    if (!groupType.showGroupHeader()) {
      assert(
        groupHeaderExtent == spacing,
        '''groupHeaderExtent should be equal to spacing when group header is not 
        shown since the header is just replaced by the grid's main axis spacing''',
      );
    }
  }

  static const double spacing = 2.0;
  // Product decision: limit how tall the preferred justified row can grow as
  // the gallery widens.
  static const double _maximumJustifiedTargetRowHeight = 320.0;

  late final int crossAxisCount;
  late final GalleryLayoutType layoutType;
  late final List<SectionLayout> _groupLayouts;
  final List<EnteFile> _allFilesWithDummies = [];

  final List<String> _groupIds = [];
  final Map<String, List<EnteFile>> _groupIdToFilesMap = {};
  final Map<
    String,
    ({GroupType groupType, int maxCreationTime, int minCreationTime})
  >
  _groupIdToGroupDataMap = {};
  final Map<double, String> _scrollOffsetToGroupIdMap = {};
  final Map<String, double> _groupIdToScrollOffsetMap = {};
  final List<double> _groupScrollOffsets = [];
  final List<({String groupID, String title})> _scrollbarDivisions = [];
  final currentUserID = Configuration.instance.getUserID();
  final _uuid = const Uuid();

  List<String> get groupIDs => _groupIds;
  Map<String, List<EnteFile>> get groupIDToFilesMap => _groupIdToFilesMap;
  Map<String, ({GroupType groupType, int maxCreationTime, int minCreationTime})>
  get groupIdToGroupDataMap => _groupIdToGroupDataMap;
  Map<double, String> get scrollOffsetToGroupIdMap => _scrollOffsetToGroupIdMap;
  Map<String, double> get groupIdToScrollOffsetMap => _groupIdToScrollOffsetMap;
  List<SectionLayout> get groupLayouts => _groupLayouts;
  List<double> get groupScrollOffsets => _groupScrollOffsets;
  List<({String groupID, String title})> get scrollbarDivisions =>
      _scrollbarDivisions;

  List<EnteFile> get allFilesWithDummies => _allFilesWithDummies;

  double? getOffsetOfGroupContainingFile(EnteFile file) {
    final creationTime = file.creationTime;
    if (creationTime == null) {
      _logger.warning('Cannot scroll to file with null creation time');
      return null;
    }

    final groupId = _findGroupForCreationTime(creationTime);
    if (groupId == null) {
      _logger.warning('No group found for creation time: $creationTime');
      return null;
    }

    final scrollOffset = _groupIdToScrollOffsetMap[groupId];
    if (scrollOffset == null) {
      _logger.warning('No scroll offset found for group: $groupId');
      return null;
    }

    return scrollOffset;
  }

  EnteFile? getFileAtScrollOffset(double scrollOffset) {
    if (_groupLayouts.isEmpty || !scrollOffset.isFinite) return null;
    final section = _groupLayouts.sectionForOffset(scrollOffset);
    if (section == null) return null;
    final groupIndex = _groupLayouts.indexOf(section);
    if (groupIndex < 0 || groupIndex >= _groupIds.length) return null;
    final files = _groupIdToFilesMap[_groupIds[groupIndex]];
    if (files == null || files.isEmpty) return null;

    final childIndex = section.getMinChildIndexForScrollOffset(scrollOffset);
    if (childIndex <= section.firstIndex) return files.first;
    final rowIndex = childIndex - section.bodyFirstIndex;
    final fileIndex = switch (section) {
      FixedExtentSectionLayout() => rowIndex * crossAxisCount,
      JustifiedSectionLayout() => section.rows[rowIndex].firstIndex,
      _ => 0,
    };
    return files[fileIndex.clamp(0, files.length - 1)];
  }

  ({double headerExtent, double rowOffset, double rowExtent})?
  getGeometryOfFile(EnteFile file) {
    final location = _findExactFileLocation(file);
    if (location == null) return null;
    final groupIndex = location.groupIndex;
    final fileIndex = location.fileIndex;
    final section = _groupLayouts[groupIndex];

    return switch (section) {
      FixedExtentSectionLayout() => (
        headerExtent: section.headerExtent,
        rowOffset:
            section.bodyMinOffset +
            (fileIndex ~/ crossAxisCount) * section.mainAxisStride,
        rowExtent: section.tileHeight,
      ),
      JustifiedSectionLayout() => () {
        final row =
            section.rows[_justifiedRowIndexForFile(section.rows, fileIndex)];
        return (
          headerExtent: section.headerExtent,
          rowOffset: section.bodyMinOffset + row.minOffset,
          rowExtent: row.height,
        );
      }(),
      _ => null,
    };
  }

  double? getOffsetOfFile(EnteFile file) => getGeometryOfFile(file)?.rowOffset;

  ({int groupIndex, int fileIndex})? _findExactFileLocation(EnteFile file) {
    ({int groupIndex, int fileIndex})? generatedIDLocation;
    ({int groupIndex, int fileIndex})? uploadedFileIDLocation;
    ({int groupIndex, int fileIndex})? localIDLocation;
    for (var groupIndex = 0; groupIndex < _groupIds.length; groupIndex++) {
      final files = _groupIdToFilesMap[_groupIds[groupIndex]]!;
      for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
        final candidate = files[fileIndex];
        if (identical(candidate, file)) {
          return (groupIndex: groupIndex, fileIndex: fileIndex);
        }
        if (candidate is DummyFile || file is DummyFile) continue;
        final location = (groupIndex: groupIndex, fileIndex: fileIndex);
        if (file.generatedID != null &&
            candidate.generatedID == file.generatedID) {
          generatedIDLocation ??= location;
        }
        if (file.uploadedFileID != null &&
            candidate.uploadedFileID == file.uploadedFileID) {
          uploadedFileIDLocation ??= location;
        }
        if (file.localID != null &&
            file.localID!.isNotEmpty &&
            candidate.localID == file.localID) {
          localIDLocation ??= location;
        }
      }
    }
    return generatedIDLocation ?? uploadedFileIDLocation ?? localIDLocation;
  }

  int _justifiedRowIndexForFile(List<JustifiedRowLayout> rows, int fileIndex) {
    var low = 0;
    var high = rows.length - 1;
    while (low <= high) {
      final mid = (low + high) >>> 1;
      final row = rows[mid];
      if (fileIndex < row.firstIndex) {
        high = mid - 1;
      } else if (fileIndex > row.lastIndex) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return rows.length - 1;
  }

  String? _findGroupForCreationTime(int creationTime) {
    if (_groupIds.isEmpty) {
      _logger.warning(
        'empty group IDs list, cannot find group for creation time: $creationTime',
      );
      return null;
    }
    int left = 0;
    int right = _groupIds.length - 1;

    while (left <= right) {
      final mid = (left + right) ~/ 2;
      final groupId = _groupIds[mid];
      final groupData = _groupIdToGroupDataMap[groupId];

      if (groupData == null) {
        _logger.warning('No group data found for group: $groupId');
        return null;
      }

      final maxTime = groupData.maxCreationTime;
      final minTime = groupData.minCreationTime;

      if (creationTime <= maxTime && creationTime >= minTime) {
        return groupId;
      } else if (sortOrderAsc) {
        if (creationTime < minTime) {
          right = mid - 1;
        } else if (creationTime > maxTime) {
          left = mid + 1;
        }
      } else {
        if (creationTime > maxTime) {
          right = mid - 1;
        } else if (creationTime < minTime) {
          left = mid + 1;
        }
      }
    }

    _logger.warning(
      '_findGroupForCreationTime No group found for creation time: $creationTime',
    );
    return null;
  }

  void init() {
    crossAxisCount = localSettings.getPhotoGridSize();
    layoutType = resolveGalleryLayoutType(
      layoutTypeOverride ?? localSettings.getGalleryLayoutType(),
      justifiedLayoutAvailable: justifiedLayoutAvailable,
    );
    _buildGroups();

    _groupLayouts = switch (layoutType) {
      GalleryLayoutType.grid => _computeFixedGroupLayouts(),
      GalleryLayoutType.justified => _computeJustifiedGroupLayouts(),
    };

    assert(groupIDs.length == _groupIdToFilesMap.length);
    assert(groupIDs.length == _groupIdToGroupDataMap.length);
    assert(groupIDs.length == _scrollOffsetToGroupIdMap.length);
    assert(groupIDs.length == _groupIdToScrollOffsetMap.length);
    assert(groupIDs.length == _groupScrollOffsets.length);
  }

  Widget _buildGroupHeader(
    BuildContext context,
    String groupID,
    List<EnteFile> filesInGroup,
    int rowIndex,
  ) {
    if (!groupType.showGroupHeader()) {
      return const SizedBox(height: spacing);
    }
    return GroupHeaderWidget(
      title: _groupIdToGroupDataMap[groupID]!.groupType.getTitle(
        context,
        filesInGroup.first,
      ),
      gridSize: crossAxisCount,
      filesInGroup: filesInGroup,
      selectedFiles: selectedFiles,
      showSelectAll: showSelectAll && !limitSelectionToOne,
      showGalleryLayoutSettingCTA: rowIndex == 0 && showGallerySettingsCTA,
    );
  }

  void _registerGroupScrollOffset(String groupID, double scrollOffset) {
    _scrollOffsetToGroupIdMap[scrollOffset] = groupID;
    _groupIdToScrollOffsetMap[groupID] = scrollOffset;
    _groupScrollOffsets.add(scrollOffset);
  }

  List<SectionLayout> _computeFixedGroupLayouts() {
    final stopwatch = Stopwatch()..start();
    int currentIndex = 0;
    double currentOffset = 0.0;
    final tileHeight =
        (widthAvailable - (crossAxisCount - 1) * spacing) / crossAxisCount;
    final groupLayouts = <SectionLayout>[];

    final groupIDs = _groupIdToFilesMap.keys;

    for (final groupID in groupIDs) {
      final filesInGroup = _groupIdToFilesMap[groupID]!;
      final numberOfGridRows = (filesInGroup.length / crossAxisCount).ceil();
      final firstIndex = currentIndex == 0 ? currentIndex : currentIndex + 1;
      final lastIndex = firstIndex + numberOfGridRows;
      final minOffset = currentOffset;
      final maxOffset =
          minOffset +
          (numberOfGridRows * tileHeight) +
          (numberOfGridRows - 1) * spacing +
          groupHeaderExtent;
      final bodyFirstIndex = firstIndex + 1;

      groupLayouts.add(
        FixedExtentSectionLayout(
          firstIndex: firstIndex,
          lastIndex: lastIndex,
          minOffset: minOffset,
          maxOffset: maxOffset,
          headerExtent: groupHeaderExtent,
          tileHeight: tileHeight,
          spacing: spacing,
          builder: (context, rowIndex) {
            if (rowIndex == firstIndex) {
              return _buildGroupHeader(
                context,
                groupID,
                filesInGroup,
                rowIndex,
              );
            } else {
              final gridRowChildren = <Widget>[];
              final firstIndexOfRowWrtFilesInGroup =
                  (rowIndex - bodyFirstIndex) * crossAxisCount;

              if (rowIndex == lastIndex) {
                final lastFile = filesInGroup.last;
                bool endOfListReached = false;
                int i = 0;
                while (!endOfListReached) {
                  final currentFile =
                      filesInGroup[firstIndexOfRowWrtFilesInGroup + i];

                  if (currentFile is DummyFile) {
                    gridRowChildren.add(
                      RepaintBoundary(
                        key: ValueKey(tagPrefix + currentFile.tag),
                        child: DummyFileWidget(
                          file: currentFile,
                          selectedFiles: selectedFiles,
                          limitSelectionToOne: limitSelectionToOne,
                        ),
                      ),
                    );
                  } else {
                    gridRowChildren.add(
                      RepaintBoundary(
                        key: ValueKey(tagPrefix + currentFile.tag),
                        child: GalleryFileWidget(
                          file: currentFile,
                          selectedFiles: selectedFiles,
                          limitSelectionToOne: limitSelectionToOne,
                          tag: tagPrefix,
                          photoGridSize: crossAxisCount,
                          currentUserID: currentUserID,
                        ),
                      ),
                    );
                  }

                  endOfListReached = currentFile == lastFile;
                  i++;
                }
              } else {
                for (int i = 0; i < crossAxisCount; i++) {
                  gridRowChildren.add(
                    RepaintBoundary(
                      key: ValueKey(
                        tagPrefix +
                            filesInGroup[firstIndexOfRowWrtFilesInGroup + i]
                                .tag,
                      ),
                      child: GalleryFileWidget(
                        file: filesInGroup[firstIndexOfRowWrtFilesInGroup + i],
                        selectedFiles: selectedFiles,
                        limitSelectionToOne: limitSelectionToOne,
                        tag: tagPrefix,
                        photoGridSize: crossAxisCount,
                        currentUserID: currentUserID,
                      ),
                    ),
                  );
                }
              }

              return FixedExtentGridRow(
                width: tileHeight,
                height: tileHeight,
                spacing: spacing,
                textDirection: TextDirection.ltr,
                children: gridRowChildren,
              );
            }
          },
        ),
      );

      _registerGroupScrollOffset(groupID, currentOffset);

      currentIndex = lastIndex;
      currentOffset = maxOffset;
    }

    _logger.info("Built group layouts in ${stopwatch.elapsedMilliseconds} ms");
    stopwatch.stop();

    return groupLayouts;
  }

  List<SectionLayout> _computeJustifiedGroupLayouts() {
    final stopwatch = Stopwatch()..start();
    final gridTargetRowHeight =
        (widthAvailable - (crossAxisCount - 1) * spacing) / crossAxisCount;
    final targetRowHeight = gridTargetRowHeight.isFinite
        ? math.min(gridTargetRowHeight, _maximumJustifiedTargetRowHeight)
        : gridTargetRowHeight;
    final groupLayouts = <SectionLayout>[];
    var currentIndex = 0;
    var currentOffset = 0.0;

    for (final groupID in _groupIdToFilesMap.keys) {
      final filesInGroup = _groupIdToFilesMap[groupID]!;
      final rows = JustifiedLayoutCalculator.computeRows(
        aspectRatios: filesInGroup.map(
          (file) => JustifiedLayoutCalculator.aspectRatioForDimensions(
            file.width,
            file.height,
          ),
        ),
        availableWidth: widthAvailable,
        targetRowHeight: targetRowHeight,
        spacing: spacing,
      );
      final firstIndex = currentIndex == 0 ? currentIndex : currentIndex + 1;
      final lastIndex = firstIndex + rows.length;
      final minOffset = currentOffset;
      final maxOffset = minOffset + groupHeaderExtent + rows.last.maxOffset;
      final bodyFirstIndex = firstIndex + 1;

      groupLayouts.add(
        JustifiedSectionLayout(
          firstIndex: firstIndex,
          lastIndex: lastIndex,
          minOffset: minOffset,
          maxOffset: maxOffset,
          headerExtent: groupHeaderExtent,
          spacing: spacing,
          rows: rows,
          builder: (context, rowIndex) {
            if (rowIndex == firstIndex) {
              return _buildGroupHeader(
                context,
                groupID,
                filesInGroup,
                rowIndex,
              );
            }

            final row = rows[rowIndex - bodyFirstIndex];
            final rowChildren = <Widget>[];
            for (
              var fileIndex = row.firstIndex;
              fileIndex <= row.lastIndex;
              fileIndex++
            ) {
              final file = filesInGroup[fileIndex];
              rowChildren.add(
                RepaintBoundary(
                  key: ValueKey(tagPrefix + file.tag),
                  child: GalleryFileWidget(
                    file: file,
                    selectedFiles: selectedFiles,
                    limitSelectionToOne: limitSelectionToOne,
                    tag: tagPrefix,
                    photoGridSize: crossAxisCount,
                    thumbnailSize: thumbnailLargeSize,
                    currentUserID: currentUserID,
                  ),
                ),
              );
            }

            return JustifiedGridRow(
              itemWidths: row.itemWidths,
              height: row.height,
              spacing: spacing,
              textDirection: TextDirection.ltr,
              children: rowChildren,
            );
          },
        ),
      );

      _registerGroupScrollOffset(groupID, currentOffset);

      currentIndex = lastIndex;
      currentOffset = maxOffset;
    }

    _logger.info(
      "Built justified group layouts in ${stopwatch.elapsedMilliseconds} ms",
    );
    stopwatch.stop();
    return groupLayouts;
  }

  void _buildGroups() {
    final stopwatch = Stopwatch()..start();

    final yearsInGroups = <int>{};

    if (groupType.showGroupHeader()) {
      var start = 0;
      for (final end in _timeGroupEndIndexes()) {
        _createNewGroup(_copyFilesInRange(start, end), yearsInGroups);
        start = end;
      }
    } else if (layoutType == GalleryLayoutType.justified) {
      if (allFiles.isNotEmpty) {
        _createNewGroup(_copyFilesInRange(0, allFiles.length), yearsInGroups);
      }
    } else {
      // Split allFiles into groups of max length 10 * crossAxisCount for
      // better performance since SectionedSliverList is used.
      for (int i = 0; i < allFiles.length; i += 10 * crossAxisCount) {
        final end = (i + 10 * crossAxisCount < allFiles.length)
            ? i + 10 * crossAxisCount
            : allFiles.length;
        final subGroup = _copyFilesInRange(i, end);
        _createNewGroup(subGroup, yearsInGroups);
      }
    }

    _logger.info(
      "Built ${_groupIds.length} groups for group type ${groupType.name} in ${stopwatch.elapsedMilliseconds} ms",
    );
    stopwatch.stop();
  }

  List<EnteFile> _copyFilesInRange(int start, int end) {
    // Create a real List<EnteFile> so _createNewGroup can add DummyFiles.
    // A sublist of List<EnteTrashFile>, for example, only accepts EnteTrashFile.
    return List<EnteFile>.from(allFiles.getRange(start, end));
  }

  List<int> _timeGroupEndIndexes() {
    final ends = <int>[];
    if (allFiles.isEmpty) {
      return ends;
    }

    var groupRange = groupType.getGroupRange(allFiles.first);
    for (var index = 1; index < allFiles.length; index++) {
      final creationTime = allFiles[index].creationTime!;
      if (creationTime < groupRange.$1 || creationTime > groupRange.$2) {
        ends.add(index);
        groupRange = groupType.getGroupRange(allFiles[index]);
      }
    }
    ends.add(allFiles.length);
    return ends;
  }

  void _createNewGroup(List<EnteFile> groupFiles, Set<int> yearsInGroups) {
    final uuid = _uuid.v1();

    final lastFile = groupFiles.last;

    // Dummy files are used for gesture tracking in swipe-to-select
    if (layoutType == GalleryLayoutType.grid && !limitSelectionToOne) {
      final incompleteRowCount = groupFiles.length % crossAxisCount;
      if (incompleteRowCount != 0) {
        final dummiesNeeded = crossAxisCount - incompleteRowCount;
        for (int i = 0; i < dummiesNeeded; i++) {
          groupFiles.add(DummyFile(groupID: uuid, index: i));
        }
      }
    }

    _groupIds.add(uuid);
    _groupIdToFilesMap[uuid] = groupFiles;
    final firstCreationTime = groupFiles.first.creationTime!;
    final lastCreationTime = lastFile.creationTime!;
    final maxCreationTime = firstCreationTime > lastCreationTime
        ? firstCreationTime
        : lastCreationTime;
    final minCreationTime = firstCreationTime < lastCreationTime
        ? firstCreationTime
        : lastCreationTime;

    _groupIdToGroupDataMap[uuid] = (
      groupType: groupType,
      maxCreationTime: maxCreationTime,
      minCreationTime: minCreationTime,
    );

    if (!limitSelectionToOne) {
      _allFilesWithDummies.addAll(groupFiles);
    }

    if (groupType.timeGrouping()) {
      final yearOfGroup = DateTime.fromMicrosecondsSinceEpoch(
        groupFiles.first.creationTime!,
      ).year;
      if (!yearsInGroups.contains(yearOfGroup)) {
        yearsInGroups.add(yearOfGroup);
        _scrollbarDivisions.add((groupID: uuid, title: yearOfGroup.toString()));
      }
    }
  }
}
