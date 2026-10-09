import "dart:io";

import "package:ente_components/ente_components.dart" as components;
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/gallery_type.dart';
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/hierarchical/face_filter.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/models/search/hierarchical/only_them_filter.dart";
import 'package:photos/models/selected_files.dart';
import "package:photos/ui/components/bottom_action_bar/action_bar_widget.dart";
import "package:photos/ui/viewer/actions/file_selection_actions_widget.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import "package:photos/ui/viewer/gallery/state/boundary_reporter_mixin.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/inherited_search_filter_data.dart";
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class FileSelectionOverlayBar extends StatefulWidget {
  final GalleryType galleryType;
  final SelectedFiles selectedFiles;
  final Collection? collection;
  final Color? backgroundColor;
  final PersonEntity? person;
  final String? clusterID;

  const FileSelectionOverlayBar(
    this.galleryType,
    this.selectedFiles, {
    this.collection,
    this.backgroundColor,
    this.person,
    this.clusterID,
    super.key,
  });

  @override
  State<FileSelectionOverlayBar> createState() =>
      _FileSelectionOverlayBarState();
}

class _FileSelectionOverlayBarState extends State<FileSelectionOverlayBar>
    with BoundaryReporter {
  final ValueNotifier<bool> _hasSelectedFilesNotifier = ValueNotifier(false);
  late GalleryType _galleryType;
  SearchFilterDataProvider? _searchFilterDataProvider;
  bool? _galleryInitialFilterStillApplied;
  bool _wasEmpty = true;
  static const Duration animationDuration = components.Motion.slow;

  @override
  void initState() {
    super.initState();
    _galleryType = widget.galleryType;
    _wasEmpty = widget.selectedFiles.files.isEmpty;
    widget.selectedFiles.addListener(_selectedFilesListener);
    widget.selectedFiles.addListener(_boundaryUpdateListener);

    if (widget.selectedFiles.files.isNotEmpty) {
      _selectedFilesListener();
    }
  }

  @override
  void dispose() {
    _hasSelectedFilesNotifier.dispose();
    widget.selectedFiles.removeListener(_selectedFilesListener);
    widget.selectedFiles.removeListener(_boundaryUpdateListener);
    _searchFilterDataProvider?.removeListener(
      listener: _filterAppliedListener,
      fromApplied: true,
    );
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FileSelectionOverlayBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _galleryType = widget.galleryType;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inheritedSearchFilterData = InheritedSearchFilterData.maybeOf(
      context,
    );
    if (inheritedSearchFilterData?.isHierarchicalSearchable ?? false) {
      _searchFilterDataProvider =
          inheritedSearchFilterData!.searchFilterDataProvider;

      _searchFilterDataProvider!.removeListener(
        listener: _filterAppliedListener,
        fromApplied: true,
      );
      _searchFilterDataProvider!.addListener(
        listener: _filterAppliedListener,
        toApplied: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '$runtimeType building with ${widget.selectedFiles.files.length}',
    );

    return _galleryType == GalleryType.homepage
        ? _body()
        : PopScope(
            // canPop=false disables iOS's back gesture.
            canPop: Platform.isIOS,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;

              if (widget.selectedFiles.files.isEmpty) {
                Navigator.of(context).pop();
                return;
              }

              widget.selectedFiles.clearAll();
            },
            child: _body(),
          );
  }

  Widget _body() {
    return ValueListenableBuilder(
      valueListenable: _hasSelectedFilesNotifier,
      builder: (context, value, child) {
        return AnimatedCrossFade(
          firstCurve: Curves.easeOutCubic,
          secondCurve: Curves.easeOutCubic,
          sizeCurve: Curves.easeOutCubic,
          crossFadeState: _hasSelectedFilesNotifier.value
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : animationDuration,
          firstChild: NotificationListener<DraggableScrollableNotification>(
            onNotification: (_) {
              reportBoundary(BoundaryPosition.bottom);
              return true;
            },
            child: boundaryWidget(
              position: BoundaryPosition.bottom,
              child: FileSelectionActionsWidget(
                _galleryType,
                widget.selectedFiles,
                collection: widget.collection,
                person: widget.person,
                clusterID: widget.clusterID,
                selectionControls: SafeArea(
                  top: false,
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: components.Spacing.sm,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(child: SelectAllButton()),
                        const SizedBox(width: components.Spacing.sm),
                        Flexible(
                          child: ActionBarWidget(
                            selectedFiles: widget.selectedFiles,
                            onCancel: widget.selectedFiles.clearAll,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                backgroundColor: widget.backgroundColor,
              ),
            ),
          ),
          secondChild: const SizedBox(width: double.infinity),
        );
      },
    );
  }

  void _selectedFilesListener() {
    _hasSelectedFilesNotifier.value = widget.selectedFiles.files.isNotEmpty;
  }

  void _boundaryUpdateListener() {
    Future.delayed(_FileSelectionOverlayBarState.animationDuration, () {
      if (!mounted) return;
      final isEmpty = widget.selectedFiles.files.isEmpty;

      if (_wasEmpty != isEmpty) {
        reportBoundary(BoundaryPosition.bottom);
        _wasEmpty = isEmpty;
      }
    });
  }

  void _filterAppliedListener() {
    widget.selectedFiles.clearAll();
    _updateGalleryTypeIfRequired();
  }

  // Once the initial filter is removed, this remains a search-results gallery.
  void _updateGalleryTypeIfRequired() {
    if (_galleryInitialFilterStillApplied != null &&
        !_galleryInitialFilterStillApplied!) {
      return;
    }

    final appliedFilters = _searchFilterDataProvider!.appliedFilters;
    final initialFilter = _searchFilterDataProvider!.initialGalleryFilter;
    bool initalFilterIsInAppliedFiters = false;
    for (HierarchicalSearchFilter filter in appliedFilters) {
      if (filter.isSameFilter(initialFilter)) {
        initalFilterIsInAppliedFiters = true;
        break;
      }
      if (initialFilter is FaceFilter) {
        for (HierarchicalSearchFilter filter in appliedFilters) {
          if (filter is OnlyThemFilter) {
            if (filter.faceFilters.any(
              (faceFilter) => faceFilter.isSameFilter(initialFilter),
            )) {
              initalFilterIsInAppliedFiters = true;
              break;
            }
          }
        }
      }
    }

    if (!initalFilterIsInAppliedFiters) {
      setState(() {
        _galleryInitialFilterStillApplied = false;
        _galleryType = GalleryType.searchResults;
      });
    } else {
      _galleryInitialFilterStillApplied = true;
    }
  }
}

class SelectAllButton extends StatelessWidget {
  const SelectAllButton({super.key});

  @override
  Widget build(BuildContext context) {
    final selectionState = SelectionState.of(context);
    if (selectionState == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: selectionState.selectedFiles,
      builder: (context, _) {
        final allGalleryFiles = GalleryFilesState.of(
          context,
        ).galleryFilesOrNull;
        if (allGalleryFiles == null) return const SizedBox.shrink();
        final allSelected =
            selectionState.selectedFiles.files.length == allGalleryFiles.length;
        return SelectionControlChip(
          label: context.strings.selectAllShort,
          semanticLabel: context.strings.selectAll,
          isSelected: allSelected,
          icon: SelectAllStatusIcon(
            isSelected: allSelected,
            size: components.IconSizes.small,
            unselectedColor: components.ComponentTheme.colorsOf(
              context,
            ).textLighter,
          ),
          onTap: allGalleryFiles.isEmpty
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  if (allSelected) {
                    selectionState.selectedFiles.clearAll();
                  } else {
                    selectionState.selectedFiles.selectAll(
                      allGalleryFiles.toSet(),
                    );
                  }
                },
        );
      },
    );
  }
}
