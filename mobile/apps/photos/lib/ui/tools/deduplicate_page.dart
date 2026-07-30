import "dart:developer";

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/user_details_changed_event.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/duplicate_files.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/services/collections_service.dart';
import "package:photos/theme/ente_theme.dart";
import 'package:photos/ui/components/buttons/button_widget.dart';
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import 'package:photos/ui/viewer/file/detail_page.dart';
import 'package:photos/ui/viewer/file/thumbnail_widget.dart';
import 'package:photos/ui/viewer/gallery/empty_state.dart';
import 'package:photos/utils/delete_file_util.dart';
import "package:photos/utils/dialog_util.dart";

class DeduplicatePage extends StatefulWidget {
  final List<DuplicateFiles> duplicates;

  const DeduplicatePage(this.duplicates, {super.key});

  @override
  State<DeduplicatePage> createState() => _DeduplicatePageState();
}

class _DeduplicatePageState extends State<DeduplicatePage> {
  static const crossAxisCount = 3;
  static const crossAxisSpacing = 12.0;

  final Set<int> selectedGrids = <int>{};

  late List<DuplicateFiles> _duplicates;

  SortKey sortKey = SortKey.size;
  late ValueNotifier<String> _deleteProgress;

  @override
  void initState() {
    _duplicates = widget.duplicates;
    _deleteProgress = ValueNotifier("");

    _selectAllGrids();
    super.initState();
  }

  @override
  void dispose() {
    _deleteProgress.dispose();

    super.dispose();
  }

  void _selectAllGrids() {
    selectedGrids.clear();
    for (int idx = 0; idx < _duplicates.length; idx++) {
      selectedGrids.add(idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    _sortDuplicates();
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(AppLocalizations.of(context).deduplicateFiles),
        actions: _duplicates.isNotEmpty ? [_getSortMenu()] : null,
      ),
      body: _getBody(),
    );
  }

  void _sortDuplicates() {
    _duplicates.sort((first, second) {
      switch (sortKey) {
        case SortKey.size:
          final aSize = first.files.length * first.size;
          final bSize = second.files.length * second.size;
          return bSize - aSize;
        case SortKey.count:
          return second.files.length - first.files.length;
      }
    });
  }

  Widget _getBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _duplicates.isNotEmpty
              ? ListView.builder(
                  cacheExtent: 400,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _getGridView(_duplicates[index], index),
                    );
                  },
                  itemCount: _duplicates.length,
                  shrinkWrap: true,
                )
              : const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: EmptyState(),
                ),
        ),
        selectedGrids.isEmpty
            ? const SizedBox.shrink()
            : Column(
                children: [
                  ValueListenableBuilder(
                    valueListenable: _deleteProgress,
                    builder: (BuildContext context, value, Widget? child) {
                      if (value.isEmpty) {
                        return const SizedBox.shrink();
                      } else {
                        return Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(
                            value, // Show the value
                            style: getEnteTextTheme(context).bodyMuted,
                          ),
                        );
                      }
                    },
                  ),
                  _getDeleteButton(),
                  const SizedBox(height: crossAxisSpacing / 2),
                ],
              ),
      ],
    );
  }

  Widget _getSortMenu() {
    final textTheme = getEnteTextTheme(context);
    Text sortOptionText(SortKey key) {
      String text = key.toString();
      switch (key) {
        case SortKey.count:
          text = AppLocalizations.of(context).count;
          break;
        case SortKey.size:
          text = AppLocalizations.of(context).totalSize;
          break;
      }
      return Text(text, style: textTheme.miniBold);
    }

    return PopupMenuButton(
      initialValue: sortKey.index,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
        child: Icon(
          Icons.sort,
          color: getEnteColorScheme(context).strokeBase,
          size: 20,
        ),
      ),
      onSelected: (int index) {
        setState(() {
          final newKey = SortKey.values[index];
          if (newKey == sortKey) {
            return;
          } else {
            sortKey = newKey;
            if (selectedGrids.length != _duplicates.length) {
              selectedGrids.clear();
            }
          }
        });
      },
      itemBuilder: (context) {
        return List.generate(SortKey.values.length, (index) {
          return PopupMenuItem(
            value: index,
            child: Text(
              sortOptionText(SortKey.values[index]).data!,
              style: textTheme.miniBold,
            ),
          );
        });
      },
    );
  }

  Widget _getDeleteButton() {
    int fileCount = 0;
    int totalSize = 0;
    for (int index = 0; index < _duplicates.length; index++) {
      if (selectedGrids.contains(index)) {
        final int toDeleteCount = _duplicates[index].files.length - 1;
        fileCount += toDeleteCount;
        totalSize += toDeleteCount * _duplicates[index].size;
      }
    }
    final hasSelectedFiles = fileCount > 0;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: hasSelectedFiles
          ? SafeArea(
              child: Container(
                key: const ValueKey('bottom_buttons'),
                padding: const EdgeInsets.symmetric(
                  horizontal: crossAxisSpacing,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: getEnteColorScheme(context).backgroundColour,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ButtonWidget(
                        labelText:
                            "${AppLocalizations.of(context).deleteItemCount(count: fileCount)} (${formatBytes(totalSize)})",
                        buttonType: ButtonType.critical,
                        onTap: () async {
                          try {
                            await deleteDuplicates(totalSize);
                          } catch (e) {
                            log("Failed to delete duplicates", error: e);
                            if (!mounted) return;
                            showGenericErrorDialog(
                              context: context,
                              error: e,
                            ).ignore();
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ButtonWidget(
                        labelText: AppLocalizations.of(context).unselectAll,
                        buttonType: ButtonType.secondary,
                        onTap: () async {
                          setState(() {
                            selectedGrids.clear();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('empty')),
    );
  }

  Future<void> deleteDuplicates(int totalSize) async {
    final List<EnteFile> filesToDelele = [];
    final Map<int, List<EnteFile>> collectionToFilesToAddMap = {};
    for (int index = 0; index < _duplicates.length; index++) {
      if (selectedGrids.contains(index)) {
        final sortedFiles = _duplicates[index].sortByLocalIDs();
        final EnteFile fileToKeep = sortedFiles.first;
        filesToDelele.addAll(sortedFiles.sublist(1));
        for (final collectionID in _duplicates[index].collectionIDs) {
          if (fileToKeep.collectionID == collectionID) {
            continue;
          }
          if (!collectionToFilesToAddMap.containsKey(collectionID)) {
            collectionToFilesToAddMap[collectionID] = [];
          }
          collectionToFilesToAddMap[collectionID]!.add(fileToKeep);
        }
      }
    }
    final int collectionCnt = collectionToFilesToAddMap.keys.length;
    int progress = 0;
    for (final collectionID in collectionToFilesToAddMap.keys) {
      if (!mounted) {
        return;
      }
      log(
        "AddingNow ${collectionToFilesToAddMap[collectionID]!.length} files to $collectionID",
      );
      await CollectionsService.instance.addSilentlyToCollection(
        collectionID,
        collectionToFilesToAddMap[collectionID]!,
      );
      if (collectionCnt > 0) {
        progress++;
        final int percentage = ((progress * 100) / collectionCnt).round();
        _deleteProgress.value = '$percentage%';
      }
    }
    _deleteProgress.value = "";
    if (filesToDelele.isNotEmpty) {
      if (!mounted) return;
      await deleteFilesFromRemoteOnly(context, filesToDelele);
      Bus.instance.fire(UserDetailsChangedEvent());
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(DeduplicationResult(filesToDelele.length, totalSize));
    }
  }

  Widget _getGridView(DuplicateFiles duplicates, int itemIndex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            crossAxisSpacing,
            4,
            crossAxisSpacing,
            12,
          ),
          child: GestureDetector(
            onTap: () {
              if (selectedGrids.contains(itemIndex)) {
                selectedGrids.remove(itemIndex);
              } else {
                selectedGrids.add(itemIndex);
              }
              setState(() {});
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppLocalizations.of(context).duplicateItemsGroup(
                    count: duplicates.files.length,
                    formattedSize: formatBytes(duplicates.size),
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                SelectAllStatusIcon(
                  isSelected: selectedGrids.contains(itemIndex),
                  size: 18,
                  selectedFillColor: Theme.of(context).iconTheme.color,
                  selectedTickCutsOut: true,
                  unselectedColor: getEnteColorScheme(context).strokeMuted,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: crossAxisSpacing),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // to disable GridView's scrolling
            itemBuilder: (context, index) {
              return _buildFile(context, duplicates.files[index], itemIndex);
            },
            itemCount: duplicates.files.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: crossAxisSpacing,
              childAspectRatio: 0.75,
            ),
            padding: const EdgeInsets.all(0),
          ),
        ),
      ],
    );
  }

  Widget _buildFile(BuildContext context, EnteFile file, int index) {
    return GestureDetector(
      onTap: () {
        final files = _duplicates[index].files;
        routeToPage(
          context,
          DetailPage(
            DetailPageConfiguration(
              files,
              files.indexOf(file),
              "deduplicate_",
              mode: DetailPageMode.minimalistic,
            ),
          ),
          forceCustomPageRoute: true,
        );
      },
      onLongPress: () {
        HapticFeedback.lightImpact();
        final files = _duplicates[index].files;
        routeToPage(
          context,
          DetailPage(
            DetailPageConfiguration(
              files,
              files.indexOf(file),
              "deduplicate_",
              mode: DetailPageMode.minimalistic,
            ),
          ),
          forceCustomPageRoute: true,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            //the numerator will give the width of the screen excuding the whitespaces in the the grid row
            height:
                (MediaQuery.of(context).size.width -
                    (crossAxisSpacing * crossAxisCount)) /
                crossAxisCount,
            child: Hero(
              tag: "deduplicate_" + file.tag,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ThumbnailWidget(
                  file,
                  diskLoadDeferDuration: galleryThumbnailDiskLoadDeferDuration,
                  serverLoadDeferDuration:
                      galleryThumbnailServerLoadDeferDuration,
                  shouldShowLivePhotoOverlay: true,
                  key: Key("deduplicate_" + file.tag),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text(
              CollectionsService.instance
                  .getCollectionByID(file.collectionID!)!
                  .displayName,
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

enum SortKey { size, count }

class DeduplicationResult {
  final int count;
  final int size;

  DeduplicationResult(this.count, this.size);
}
