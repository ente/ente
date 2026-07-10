import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart" show kDebugMode;
import 'package:flutter/material.dart';
import "package:flutter_spinkit/flutter_spinkit.dart" show SpinKitFadingCircle;
import "package:flutter_svg/svg.dart";
import "package:intl/intl.dart";
import 'package:logging/logging.dart';
import "package:photos/core/configuration.dart";
import 'package:photos/core/constants.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/models/similar_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/services/machine_learning/similar_images_service.dart";
import "package:photos/theme/colors.dart";
import 'package:photos/theme/ente_theme.dart';
import "package:photos/theme/text_style.dart";
import 'package:photos/ui/components/buttons/button_widget.dart';
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/components/toggle_switch_widget.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/utils/delete_file_util.dart";
import "package:photos/utils/dialog_util.dart";
import 'package:rive/rive.dart' as rive;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

enum SimilarImagesPageState { setup, loading, results }

enum SortKey { size, recent, count }

enum TabFilter { close, similar, related }

class SimilarImagesPage extends StatefulWidget {
  final bool debugScreen;

  const SimilarImagesPage({super.key, this.debugScreen = false});

  @override
  State<SimilarImagesPage> createState() => _SimilarImagesPageState();
}

class _SimilarImagesPageState extends State<SimilarImagesPage>
    with SingleTickerProviderStateMixin {
  static const crossAxisCount = 3;
  static const crossAxisSpacing = 12.0;
  static const double _similarThreshold = 0.02;
  static const double _closeThreshold = 0.001;

  final _logger = Logger("SimilarImagesPage");
  bool _isDisposed = false;

  SimilarImagesPageState _pageState = SimilarImagesPageState.setup;
  double _distanceThreshold = 0.04; // Default value
  List<SimilarFiles> _similarFilesList = [];

  SortKey _sortKey = SortKey.size;
  bool _exactSearch = false;
  bool _fullRefresh = false;
  TabFilter _selectedTab = TabFilter.close;

  late SelectedFiles _selectedFiles;
  late ValueNotifier<String> _deleteProgress;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  late AnimationController deleteAnimationController;

  List<SimilarFiles> get _filteredGroups {
    final filteredGroups = <SimilarFiles>[];
    switch (_selectedTab) {
      case TabFilter.close:
        for (final group in _similarFilesList) {
          final distance = group.furthestDistance;
          if (distance <= _closeThreshold) {
            filteredGroups.add(group);
          }
        }
      case TabFilter.similar:
        for (final group in _similarFilesList) {
          final distance = group.furthestDistance;
          if (distance > _closeThreshold && distance <= _similarThreshold) {
            filteredGroups.add(group);
          }
        }
      case TabFilter.related:
        for (final group in _similarFilesList) {
          final distance = group.furthestDistance;
          if (distance > _similarThreshold) {
            filteredGroups.add(group);
          }
        }
    }
    return filteredGroups;
  }

  @override
  void initState() {
    super.initState();
    _selectedFiles = SelectedFiles();
    _deleteProgress = ValueNotifier("");
    deleteAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    if (!widget.debugScreen) {
      _findSimilarImages();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _selectedFiles.dispose();
    _deleteProgress.dispose();
    deleteAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(AppLocalizations.of(context).similarImages),
        actions: _pageState == SimilarImagesPageState.results
            ? [_getSortMenu()]
            : null,
      ),
      body: _getBody(),
    );
  }

  Widget _getBody() {
    final content = switch (_pageState) {
      SimilarImagesPageState.setup => _getSetupView(),
      SimilarImagesPageState.loading => _getLoadingView(),
      SimilarImagesPageState.results => _getResultsView(),
    };

    return Stack(
      children: [
        content,
        // Progress overlay
        ValueListenableBuilder(
          valueListenable: _deleteProgress,
          builder: (context, value, child) {
            final colorScheme = getEnteColorScheme(context);
            final textTheme = getEnteTextTheme(context);
            final fontFeatures = textTheme.small.fontFeatures ?? [];

            return AnimatedCrossFade(
              firstCurve: Curves.easeInOutExpo,
              secondCurve: Curves.easeInOutExpo,
              sizeCurve: Curves.easeInOutExpo,
              crossFadeState: value.isEmpty
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 400),
              secondChild: Align(
                alignment: Alignment.center,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ).copyWith(left: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.black.withValues(alpha: 0.72),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        child: SpinKitFadingCircle(
                          size: 18,
                          color: colorScheme.warning500,
                          controller: deleteAnimationController,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context).deletingDash,
                        style: textTheme.small.copyWith(color: Colors.white),
                      ),
                      Text(
                        value,
                        style: textTheme.small.copyWith(
                          color: Colors.white,
                          fontFeatures: [
                            const FontFeature.tabularFigures(),
                            ...fontFeatures,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              firstChild: const SizedBox.shrink(),
            );
          },
        ),
      ],
    );
  }

  Widget _getSetupView() {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 72,
            color: colorScheme.primary500,
          ),
          const SizedBox(height: 32),
          Text(
            AppLocalizations.of(context).findSimilarImages,
            style: textTheme.h3Bold,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            "Use AI to find images that look similar to each other. Adjust the distance threshold below.",
            style: textTheme.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Text("Similarity threshold", style: textTheme.bodyBold),
          const SizedBox(height: 8),
          Text("Lower values mean a closer match.", style: textTheme.miniMuted),
          const SizedBox(height: 16),
          Row(
            children: [
              Text("0.01", style: textTheme.mini),
              Expanded(
                child: Slider(
                  value: _distanceThreshold,
                  min: 0.01,
                  max: 0.15,
                  divisions: 14,
                  onChanged: (value) {
                    if (_isDisposed) return;
                    setState(() {
                      _distanceThreshold = (value * 100).round() / 100;
                    });
                  },
                ),
              ),
              Text("0.15", style: textTheme.mini),
            ],
          ),
          Text(
            "Current: ${_distanceThreshold.toStringAsFixed(2)}",
            style: textTheme.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Exact search", style: textTheme.bodyBold),
              ToggleSwitchWidget(
                value: () => _exactSearch,
                onChanged: () async {
                  if (_isDisposed) return;
                  setState(() {
                    _exactSearch = !_exactSearch;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Full refresh", style: textTheme.bodyBold),
              ToggleSwitchWidget(
                value: () => _fullRefresh,
                onChanged: () async {
                  if (_isDisposed) return;
                  setState(() {
                    _fullRefresh = !_fullRefresh;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
          ButtonWidget(
            labelText: AppLocalizations.of(context).findSimilarImages,
            buttonType: ButtonType.primary,
            onTap: () async {
              await _findSimilarImages();
            },
          ),
        ],
      ),
    );
  }

  Widget _getLoadingView() {
    return const _LoadingScreen();
  }

  Widget _getResultsView() {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    if (_similarFilesList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 72,
              color: colorScheme.primary500,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).noSimilarImagesFound,
              style: textTheme.h3Bold,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).yourPhotosLookUnique,
              style: textTheme.bodyMuted,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildTabBar(),
        Expanded(
          child: _filteredGroups.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          "assets/ducky_cleaning_static.svg",
                          height: 160,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context).nothingToTidyUpHere,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMuted,
                        ),
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                )
              : ScrollablePositionedList.builder(
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  itemCount: _filteredGroups.length,
                  itemBuilder: (context, index) {
                    if (index >= _filteredGroups.length) {
                      return const SizedBox.shrink();
                    }
                    final group = _filteredGroups[index];
                    return Column(
                      children: [
                        if (index == 0) const SizedBox(height: 16),
                        RepaintBoundary(child: _buildSimilarFilesGroup(group)),
                      ],
                    );
                  },
                ),
        ),
        if (_filteredGroups.isNotEmpty) _getBottomActionButtons(),
      ],
    );
  }

  Widget _buildTabBar() {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _buildTabButton(
            TabFilter.close,
            AppLocalizations.of(context).closeBy,
            colorScheme,
            textTheme,
          ),
          const SizedBox(width: crossAxisSpacing),
          _buildTabButton(
            TabFilter.similar,
            AppLocalizations.of(context).similar,
            colorScheme,
            textTheme,
          ),
          const SizedBox(width: crossAxisSpacing),
          _buildTabButton(
            TabFilter.related,
            AppLocalizations.of(context).related,
            colorScheme,
            textTheme,
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(
    TabFilter tab,
    String label,
    EnteColorScheme colorScheme,
    EnteTextTheme textTheme,
  ) {
    final isSelected = _selectedTab == tab;

    return GestureDetector(
      onTap: () => _onTabChanged(tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary700 : colorScheme.fillFaint,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: isSelected
              ? textTheme.smallBold.copyWith(color: Colors.white)
              : textTheme.smallBold,
        ),
      ),
    );
  }

  void _onTabChanged(TabFilter newTab) {
    setState(() {
      _selectedTab = newTab;

      final newSelection = <EnteFile>{};
      for (final group in _filteredGroups) {
        for (int i = 1; i < group.files.length; i++) {
          final file = group.files[i];
          if (FavoritesService.instance.isFavoriteCache(file)) continue;
          newSelection.add(file);
        }
      }
      _selectedFiles.clearAll();
      _selectedFiles.selectAll(newSelection);
    });
  }

  Widget _getBottomActionButtons() {
    return ListenableBuilder(
      listenable: _selectedFiles,
      builder: (context, _) {
        final eligibleFilteredFiles = <EnteFile>{};
        int autoSelectCount = 0;
        for (final group in _filteredGroups) {
          for (int i = 0; i < group.files.length; i++) {
            final file = group.files[i];
            eligibleFilteredFiles.add(file);
            if (i != 0 && !FavoritesService.instance.isFavoriteCache(file)) {
              autoSelectCount++;
            }
          }
        }
        final selectedFiles = _selectedFiles.files;

        final selectedFilteredFiles = selectedFiles.intersection(
          eligibleFilteredFiles,
        );
        final allFilteredSelected =
            eligibleFilteredFiles.isNotEmpty &&
            selectedFilteredFiles.length >= autoSelectCount;
        final hasSelectedFiles = selectedFilteredFiles.isNotEmpty;

        int totalSize = 0;
        for (final file in selectedFilteredFiles) {
          totalSize += file.fileSize ?? 0;
        }

        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: crossAxisSpacing,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: getEnteColorScheme(context).backgroundColour,
            ),
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                        return SlideTransition(
                          position:
                              Tween<Offset>(
                                begin: const Offset(0, 0.1),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                  child: hasSelectedFiles
                      ? Column(
                          key: const ValueKey('delete_section'),
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ButtonWidget(
                                labelText: AppLocalizations.of(context)
                                    .deletePhotosWithSize(
                                      count: NumberFormat().format(
                                        selectedFilteredFiles.length,
                                      ),
                                      size: formatBytes(totalSize),
                                    ),
                                buttonType: ButtonType.critical,
                                shouldSurfaceExecutionStates: false,
                                shouldShowSuccessConfirmation: false,
                                onTap: () async {
                                  await _deleteFiles(
                                    selectedFilteredFiles,
                                    showDialog: true,
                                    showUIFeedback: true,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        )
                      : const SizedBox.shrink(key: ValueKey('no_delete')),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ButtonWidget(
                    labelText: allFilteredSelected
                        ? AppLocalizations.of(context).unselectAll
                        : AppLocalizations.of(context).selectAll,
                    buttonType: ButtonType.secondary,
                    shouldSurfaceExecutionStates: false,
                    shouldShowSuccessConfirmation: false,
                    onTap: () async {
                      _toggleSelectAll(allFilteredSelected);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleSelectAll(bool allSelected) {
    final autoSelectFiles = <EnteFile>{};
    for (final group in _filteredGroups) {
      for (int i = 1; i < group.files.length; i++) {
        final file = group.files[i];
        if (FavoritesService.instance.isFavoriteCache(file)) continue;
        autoSelectFiles.add(file);
      }
    }

    if (allSelected) {
      _selectedFiles.clearAll();
    } else {
      _selectedFiles.selectAll(autoSelectFiles);
    }
  }

  int? _getTopMostVisibleIndex() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return null;
    int? topIndex;
    double? bestLeading;
    for (final p in positions) {
      final leading = p.itemLeadingEdge;
      final trailing = p.itemTrailingEdge;
      final visible = trailing > 0.0 && leading < 1.0;
      if (!visible) continue;
      if (bestLeading == null || leading < bestLeading) {
        bestLeading = leading;
        topIndex = p.index;
      }
    }
    return topIndex;
  }

  bool _groupSurvivesAfterDeletion(
    SimilarFiles group,
    Set<EnteFile> filesToDelete,
  ) {
    var remaining = 0;
    for (final file in group.files) {
      if (!filesToDelete.contains(file)) {
        remaining++;
        if (remaining > 1) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _findSimilarImages() async {
    if (_isDisposed) return;
    setState(() {
      _pageState = SimilarImagesPageState.loading;
    });

    try {
      _logger.info("exact mode: $_exactSearch");

      final similarFiles = await SimilarImagesService.instance.getSimilarFiles(
        _distanceThreshold,
        exact: _exactSearch,
        forceRefresh: _fullRefresh,
      );
      _logger.info("Found ${similarFiles.length} groups of similar images");

      _similarFilesList = similarFiles;
      _pageState = SimilarImagesPageState.results;
      _sortSimilarFiles();

      for (final group in _similarFilesList) {
        if (group.files.length > 1) {
          for (int i = 1; i < group.files.length; i++) {
            final file = group.files[i];
            if (FavoritesService.instance.isFavoriteCache(file)) continue;
            _selectedFiles.toggleSelection(file);
          }
        }
      }

      if (_isDisposed) return;
      setState(() {});

      return;
    } catch (e, s) {
      _logger.severe("Failed to get similar files", e, s);
      if (_isDisposed) return;
      if (flagService.internalUser) {
        if (!mounted) return;
        await showGenericErrorDialog(context: context, error: e);
      }
      if (_isDisposed) return;
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  int? _groupMostRecentCreationTime(SimilarFiles similarFiles) {
    int? mostRecentCreationTime;
    for (final file in similarFiles.files) {
      final creationTime = file.creationTime;
      if (creationTime == null || creationTime <= 0) {
        continue;
      }
      if (mostRecentCreationTime == null ||
          creationTime > mostRecentCreationTime) {
        mostRecentCreationTime = creationTime;
      }
    }
    return mostRecentCreationTime;
  }

  void _sortSimilarFiles({bool updateState = true}) {
    switch (_sortKey) {
      case SortKey.size:
        _similarFilesList.sort((a, b) => b.totalSize.compareTo(a.totalSize));
        break;
      case SortKey.recent:
        _similarFilesList.sort((a, b) {
          final aMostRecentCreationTime = _groupMostRecentCreationTime(a);
          final bMostRecentCreationTime = _groupMostRecentCreationTime(b);
          if (aMostRecentCreationTime == null) {
            if (bMostRecentCreationTime == null) {
              return b.totalSize.compareTo(a.totalSize);
            }
            return 1;
          }
          if (bMostRecentCreationTime == null) {
            return -1;
          }
          final recentComparison = bMostRecentCreationTime.compareTo(
            aMostRecentCreationTime,
          );
          if (recentComparison != 0) {
            return recentComparison;
          }
          return b.totalSize.compareTo(a.totalSize);
        });
        break;
      case SortKey.count:
        _similarFilesList.sort(
          (a, b) => b.files.length.compareTo(a.files.length),
        );
        break;
    }
    if (!updateState || _isDisposed) return;
    setState(() {});
  }

  Widget _buildSimilarFilesGroup(SimilarFiles similarFiles) {
    final textTheme = getEnteTextTheme(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: crossAxisSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.of(
                      context,
                    ).similarImagesCount(count: similarFiles.files.length) +
                    (kDebugMode
                        ? " (I: d: ${similarFiles.furthestDistance.toStringAsFixed(3)})"
                        : ""),
                style: textTheme.smallMuted.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(
                height: 34,
                child: ListenableBuilder(
                  listenable: _selectedFiles,
                  builder: (context, _) {
                    final groupSelectedFiles = similarFiles.files
                        .where((file) => _selectedFiles.isFileSelected(file))
                        .toSet();
                    final bool allFilesFromGroupSelected =
                        groupSelectedFiles.length == similarFiles.length;
                    if (groupSelectedFiles.isNotEmpty) {
                      return _getSmallDeleteButton(
                        groupSelectedFiles,
                        allFilesFromGroupSelected,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth =
                  (constraints.maxWidth -
                      (crossAxisSpacing * (crossAxisCount - 1))) /
                  crossAxisCount;
              final itemHeight =
                  itemWidth / 0.70; // Maintain aspect ratio from GridView

              return Wrap(
                spacing: crossAxisSpacing,
                runSpacing:
                    0, // No additional vertical spacing - items have internal bottom padding
                children: similarFiles.files.asMap().entries.map((entry) {
                  return SizedBox(
                    width: itemWidth,
                    height: itemHeight,
                    child: _buildFile(
                      context,
                      entry.value,
                      similarFiles.files,
                      entry.key,
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 16), // Add spacing between groups
        ],
      ),
    );
  }

  Widget _buildFile(
    BuildContext context,
    EnteFile file,
    List<EnteFile> allFiles,
    int index,
  ) {
    final textTheme = getEnteTextTheme(context);
    return ListenableBuilder(
      listenable: _selectedFiles,
      builder: (context, _) {
        final bool isSelected = _selectedFiles.isFileSelected(file);

        return GestureDetector(
          onTap: () {
            _selectedFiles.toggleSelection(file);
          },
          onLongPress: () {
            routeToPage(
              context,
              DetailPage(
                DetailPageConfiguration(
                  allFiles,
                  index,
                  "similar_images_",
                  mode: DetailPageMode.minimalistic,
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Hero(
                      tag: "similar_images_" + file.tag,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ThumbnailWidget(
                              file,
                              diskLoadDeferDuration:
                                  galleryThumbnailDiskLoadDeferDuration,
                              serverLoadDeferDuration:
                                  galleryThumbnailServerLoadDeferDuration,
                              shouldShowLivePhotoOverlay: true,
                              key: Key("similar_images_" + file.tag),
                            ),
                            if (isSelected)
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.black.withAlpha(
                                    (0.4 * 255).toInt(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 5,
                      right: 5,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: isSelected
                            ? const SelectAllStatusIcon(
                                isSelected: true,
                                size: 18,
                                selectedFillColor: Colors.white,
                                selectedTickCutsOut: true,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                file.displayName,
                style: textTheme.small,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(formatBytes(file.fileSize!), style: textTheme.miniMuted),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _getSmallDeleteButton(Set<EnteFile> files, bool showDialog) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    if (files.isEmpty) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () async {
        await _deleteFiles(
          files,
          showDialog: showDialog,
          showUIFeedback: false,
          maintainScrollAnchor: false,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.warning500.withAlpha((0.1 * 255).toInt()),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 12, color: colorScheme.warning500),
            const SizedBox(width: 4),
            Text(
              AppLocalizations.of(context).deleteWithCount(count: files.length),
              style: textTheme.smallBold.copyWith(
                color: colorScheme.warning500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteFiles(
    Set<EnteFile> filesToDelete, {
    bool showDialog = true,
    bool showUIFeedback = true,
    bool maintainScrollAnchor = true,
  }) async {
    if (filesToDelete.isEmpty) return;
    if (showDialog) {
      final _ = await showChoiceActionSheet(
        context,
        title: AppLocalizations.of(context).deleteFiles,
        body: AppLocalizations.of(context).areYouSureDeleteFiles,
        firstButtonLabel: AppLocalizations.of(context).delete,
        isCritical: true,
        firstButtonOnTap: () async {
          try {
            await _deleteFilesLogic(
              filesToDelete,
              true,
              showUIFeedback: showUIFeedback,
              maintainScrollAnchor: maintainScrollAnchor,
            );
          } catch (e, s) {
            _logger.severe("Failed to delete files", e, s);
            if (!mounted) return;
            await showGenericErrorDialog(context: context, error: e);
          }
        },
      );
    } else {
      try {
        await _deleteFilesLogic(
          filesToDelete,
          true,
          showUIFeedback: showUIFeedback,
          maintainScrollAnchor: maintainScrollAnchor,
        );
      } catch (e, s) {
        _logger.severe("Failed to delete files", e, s);
        if (mounted) {
          await showGenericErrorDialog(context: context, error: e);
        }
      }
    }
  }

  Future<void> _deleteFilesLogic(
    Set<EnteFile> filesToDelete,
    bool createSymlink, {
    bool showUIFeedback = true,
    bool maintainScrollAnchor = true,
  }) async {
    if (filesToDelete.isEmpty) {
      return;
    }
    SimilarFiles? anchorGroup;
    if (maintainScrollAnchor) {
      final beforeFiltered = _filteredGroups;
      final plannedDeletes = Set<EnteFile>.from(filesToDelete);
      final topIndex = _getTopMostVisibleIndex();

      bool groupAtIndexSurvives(int? index) {
        if (index == null) return false;
        if (index < 0 || index >= beforeFiltered.length) return false;
        return _groupSurvivesAfterDeletion(
          beforeFiltered[index],
          plannedDeletes,
        );
      }

      if (groupAtIndexSurvives(topIndex)) {
        anchorGroup = beforeFiltered[topIndex!];
      } else {
        final visiblePositions =
            _itemPositionsListener.itemPositions.value
                .where((p) => p.index >= 0 && p.index < beforeFiltered.length)
                .toList()
              ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
        int? lastVisibleIndex;
        for (final position in visiblePositions) {
          final idx = position.index;
          if (lastVisibleIndex == null || idx > lastVisibleIndex) {
            lastVisibleIndex = idx;
          }
          if (topIndex != null && idx == topIndex) {
            continue;
          }
          final candidate = beforeFiltered[idx];
          if (_groupSurvivesAfterDeletion(candidate, plannedDeletes)) {
            anchorGroup = candidate;
            break;
          }
        }
        if (anchorGroup == null) {
          final startIndex = (lastVisibleIndex ?? topIndex ?? -1) + 1;
          for (int i = startIndex; i < beforeFiltered.length; i++) {
            final candidate = beforeFiltered[i];
            if (_groupSurvivesAfterDeletion(candidate, plannedDeletes)) {
              anchorGroup = candidate;
              break;
            }
          }
        }
      }
    }
    final Map<int, Set<EnteFile>> collectionToFilesToAddMap = {};
    final allDeleteFiles = <EnteFile>{};
    final groupsToRemove = <SimilarFiles>{};
    for (final similarGroup in _similarFilesList) {
      final groupDeleteFiles = <EnteFile>{};
      for (final file in filesToDelete) {
        if (similarGroup.containsFile(file)) {
          similarGroup.removeFile(file);
          groupDeleteFiles.add(file);
          allDeleteFiles.add(file);
          if (similarGroup.isEmpty) {
            break;
          }
        }
      }
      if (similarGroup.length <= 1) {
        groupsToRemove.add(similarGroup);
      }
      if (groupDeleteFiles.isNotEmpty) {
        filesToDelete.removeAll(groupDeleteFiles);
      }
      if (!similarGroup.isEmpty && createSymlink) {
        final filesToKeep = similarGroup.files;
        final collectionIDs = filesToKeep
            .map((file) => file.collectionID)
            .toSet();
        for (final deletedFile in groupDeleteFiles) {
          final collectionID = deletedFile.collectionID;
          if (collectionIDs.contains(collectionID) || collectionID == null) {
            continue;
          }
          if (!collectionToFilesToAddMap.containsKey(collectionID)) {
            collectionToFilesToAddMap[collectionID] = {};
          }
          collectionToFilesToAddMap[collectionID]!.addAll(filesToKeep);
        }
      }
    }
    for (final group in groupsToRemove) {
      _similarFilesList.remove(group);
    }
    _sortSimilarFiles(updateState: false);

    final int collectionCnt = collectionToFilesToAddMap.keys.length;
    if (createSymlink) {
      final userID = Configuration.instance.getUserID();
      int progress = 0;
      for (final collectionID in collectionToFilesToAddMap.keys) {
        if (!mounted) {
          return;
        }
        // Check permission before attempting to add symlinks
        final collection = CollectionsService.instance.getCollectionByID(
          collectionID,
        );
        if (collection != null && collection.canAutoAdd(userID!)) {
          await CollectionsService.instance.addSilentlyToCollection(
            collectionID,
            collectionToFilesToAddMap[collectionID]!.toList(),
          );
        } else {
          _logger.warning(
            "Skipping adding symlinks to collection $collectionID due to missing permissions (${collection?.canAutoAdd(userID!) ?? false}) or collection not found. (${collection == null})",
          );
        }
        if (collectionCnt > 2 && showUIFeedback) {
          progress++;
          final int percentage = ((progress * 100) / collectionCnt).round();
          _deleteProgress.value = '$percentage%';
        }
      }
    }
    if (collectionCnt > 2 && showUIFeedback) {
      _deleteProgress.value = "";
    }

    _selectedFiles.unSelectAll(allDeleteFiles);
    setState(() {});
    if (maintainScrollAnchor &&
        anchorGroup != null &&
        _itemScrollController.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final afterFiltered = _filteredGroups;
        final newIndex = afterFiltered.indexWhere(
          (g) => identical(g, anchorGroup),
        );
        if (newIndex != -1 && _itemScrollController.isAttached) {
          _itemScrollController.jumpTo(index: newIndex, alignment: 0.0);
        }
      });
    }
    if (!mounted) return;
    await deleteFilesFromRemoteOnly(context, allDeleteFiles.toList());

    // Show congratulations popup
    if (allDeleteFiles.length > 100 && mounted && showUIFeedback) {
      final int totalSize = allDeleteFiles.fold<int>(
        0,
        (sum, file) => sum + (file.fileSize ?? 0),
      );
      _showCongratulationsDialog(totalSize);
    }
  }

  void _showCongratulationsDialog(int totalSize) {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final screenWidth = MediaQuery.of(context).size.width;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.backgroundElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.all(24),
        content: SizedBox(
          width: screenWidth - (crossAxisSpacing),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset("assets/ducky_cleaning_static.svg", height: 160),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).hoorayyyy,
                style: textTheme.h2Bold.copyWith(color: colorScheme.primary500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(
                  context,
                ).cleanedUpSimilarImages(size: formatBytes(totalSize)),
                style: textTheme.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ButtonWidget(
                  labelText: AppLocalizations.of(context).done,
                  buttonType: ButtonType.primary,
                  onTap: () async => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getSortMenu() {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);

    Text sortOptionText(SortKey key) {
      String text;
      switch (key) {
        case SortKey.size:
          text = AppLocalizations.of(context).totalSize;
          break;
        case SortKey.recent:
          text = AppLocalizations.of(context).recent;
          break;
        case SortKey.count:
          text = AppLocalizations.of(context).count;
          break;
      }
      return Text(text, style: textTheme.miniBold);
    }

    return PopupMenuButton(
      initialValue: _sortKey.index,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 6),
        child: Icon(Icons.sort, color: colorScheme.strokeBase, size: 20),
      ),
      onSelected: (int index) {
        if (_isDisposed) return;
        setState(() {
          final newKey = SortKey.values[index];
          if (newKey == _sortKey) {
            return;
          } else {
            _sortKey = newKey;
          }
        });
        _sortSimilarFiles();
      },
      itemBuilder: (context) {
        const sortKeys = SortKey.values;
        return List.generate(sortKeys.length, (index) {
          final sortKey = sortKeys[index];
          return PopupMenuItem(
            value: SortKey.values.indexOf(sortKey),
            child: Text(
              sortOptionText(sortKey).data!,
              style: textTheme.miniBold,
            ),
          );
        });
      },
    );
  }
}

class _LoadingScreen extends StatefulWidget {
  const _LoadingScreen();

  @override
  State<_LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<_LoadingScreen> {
  Timer? _timer;
  int _currentTextIndex = 0;

  late List<String> _loadingTexts;
  late final rive.FileLoader _analysisAnimationLoader;

  @override
  void initState() {
    super.initState();
    _analysisAnimationLoader = rive.FileLoader.fromAsset(
      'assets/ducky_analyze_files.riv',
      riveFactory: rive.Factory.flutter,
    );
    _startTextCycling();
  }

  void _startTextCycling() {
    _timer = Timer.periodic(const Duration(seconds: 7), (timer) {
      if (_currentTextIndex < _loadingTexts.length - 1) {
        if (mounted) {
          setState(() {
            _currentTextIndex++;
          });
        }
        // Stop the timer when we reach the last text
        if (_currentTextIndex >= _loadingTexts.length - 1) {
          timer.cancel();
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _analysisAnimationLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);

    _loadingTexts = [
      AppLocalizations.of(context).analyzingPhotosLocally,
      AppLocalizations.of(context).lookingForVisualSimilarities,
      AppLocalizations.of(context).comparingImageDetails,
      AppLocalizations.of(context).findingSimilarImages,
      AppLocalizations.of(context).almostDone,
    ];

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 160,
            child: rive.RiveWidgetBuilder(
              fileLoader: _analysisAnimationLoader,
              builder: (BuildContext context, rive.RiveState state) {
                if (state is rive.RiveLoaded) {
                  return rive.RiveWidget(
                    controller: state.controller,
                    fit: rive.Fit.contain,
                  );
                }
                return const SizedBox.expand();
              },
            ),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Text(
              _loadingTexts[_currentTextIndex],
              key: ValueKey<int>(_currentTextIndex),
              style: textTheme.bodyMuted,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
