import "dart:core";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/gallery/fixed_extent_grid_row.dart";
import "package:photos/models/gallery/fixed_extent_section_layout.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/viewer/gallery/component/dummy_file_widget.dart";
import "package:photos/ui/viewer/gallery/component/gallery_file_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/group_header_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:uuid/uuid.dart";

/// In order to make the gallery performant when GroupTypes do not show group
/// headers, groups are still created here but with the group header replaced by
/// the grid's main axis spacing.
class GalleryGroups {
  final List<EnteFile> allFiles;
  final GroupType groupType;
  final SelectedFiles? selectedFiles;
  final bool limitSelectionToOne;
  final String tagPrefix;
  final bool showSelectAll;
  final _logger = Logger("GalleryGroups");
  final bool showGallerySettingsCTA;

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

    /// Should be GroupGallery.spacing if GroupType.showGroupHeader() is false.
    required this.groupHeaderExtent,
    required this.showSelectAll,
    this.limitSelectionToOne = false,
    this.showGallerySettingsCTA = false,
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

  late final int crossAxisCount;
  late final List<FixedExtentSectionLayout> _groupLayouts;
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
  List<FixedExtentSectionLayout> get groupLayouts => _groupLayouts;
  List<double> get groupScrollOffsets => _groupScrollOffsets;
  List<({String groupID, String title})> get scrollbarDivisions =>
      _scrollbarDivisions;

  /// Returns allFiles with dummy entries added at appropriate positions to fill
  /// incomplete rows in each group.
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

  /// Uses binary search to find the group ID that contains the given creation time.
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
        // Found the group containing this creation time
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
    _buildGroups();

    _groupLayouts = _computeGroupLayouts();

    assert(groupIDs.length == _groupIdToFilesMap.length);
    assert(groupIDs.length == _groupIdToGroupDataMap.length);
    assert(groupIDs.length == _scrollOffsetToGroupIdMap.length);
    assert(groupIDs.length == _groupIdToScrollOffsetMap.length);
    assert(groupIDs.length == _groupScrollOffsets.length);
  }

  List<FixedExtentSectionLayout> _computeGroupLayouts() {
    final stopwatch = Stopwatch()..start();
    final showGroupHeader = groupType.showGroupHeader();
    int currentIndex = 0;
    double currentOffset = 0.0;
    final tileHeight =
        (widthAvailable - (crossAxisCount - 1) * spacing) / crossAxisCount;
    final groupLayouts = <FixedExtentSectionLayout>[];

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
              if (showGroupHeader) {
                return GroupHeaderWidget(
                  title: _groupIdToGroupDataMap[groupID]!.groupType.getTitle(
                    context,
                    groupIDToFilesMap[groupID]!.first,
                  ),
                  gridSize: crossAxisCount,
                  filesInGroup: groupIDToFilesMap[groupID]!,
                  selectedFiles: selectedFiles,
                  showSelectAll: showSelectAll && !limitSelectionToOne,
                  showGalleryLayoutSettingCTA:
                      rowIndex == 0 && showGallerySettingsCTA,
                );
              } else {
                return const SizedBox(height: spacing);
              }
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
                    // Add dummy widget for DummyFile
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
                    // Add normal GalleryFileWidget for real files
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

      _scrollOffsetToGroupIdMap[currentOffset] = groupID;
      _groupIdToScrollOffsetMap[groupID] = currentOffset;
      _groupScrollOffsets.add(currentOffset);

      currentIndex = lastIndex;
      currentOffset = maxOffset;
    }

    _logger.info("Built group layouts in ${stopwatch.elapsedMilliseconds} ms");
    stopwatch.stop();

    return groupLayouts;
  }

  void _buildGroups() {
    final stopwatch = Stopwatch()..start();

    final yearsInGroups = <int>{}; //Only relevant for time grouping
    List<EnteFile> groupFiles = [];
    final allFilesLength = allFiles.length;

    if (groupType.showGroupHeader()) {
      for (int index = 0; index < allFilesLength; index++) {
        if (index > 0 &&
            !groupType.areFromSameGroup(allFiles[index - 1], allFiles[index])) {
          _createNewGroup(groupFiles, yearsInGroups);
          groupFiles = [];
        }
        groupFiles.add(allFiles[index]);
      }
      if (groupFiles.isNotEmpty) {
        _createNewGroup(groupFiles, yearsInGroups);
      }
    } else {
      // Split allFiles into groups of max length 10 * crossAxisCount for
      // better performance since SectionedSliverList is used.
      for (int i = 0; i < allFiles.length; i += 10 * crossAxisCount) {
        final end = (i + 10 * crossAxisCount < allFiles.length)
            ? i + 10 * crossAxisCount
            : allFiles.length;
        final subGroup = allFiles.sublist(i, end);
        _createNewGroup(subGroup, yearsInGroups);
      }
    }

    _logger.info(
      "Built ${_groupIds.length} groups for group type ${groupType.name} in ${stopwatch.elapsedMilliseconds} ms",
    );
    stopwatch.stop();
  }

  void _createNewGroup(List<EnteFile> groupFiles, Set<int> yearsInGroups) {
    final uuid = _uuid.v1();

    // Save original last file before adding dummies to the end
    final lastFile = groupFiles.last;

    // Dummy files are used for gesture tracking in swipe-to-select
    if (!limitSelectionToOne) {
      // Add dummy files to fill the last row if needed
      final incompleteRowCount = groupFiles.length % crossAxisCount;
      if (incompleteRowCount != 0) {
        final dummiesNeeded = crossAxisCount - incompleteRowCount;
        final filesWithDummies = List<EnteFile>.from(groupFiles);
        for (int i = 0; i < dummiesNeeded; i++) {
          filesWithDummies.add(DummyFile(groupID: uuid, index: i));
        }
        groupFiles = filesWithDummies;
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

    // For scrollbar divisions
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
