import "dart:io";

import "package:ente_components/ente_components.dart" as components;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/gallery_type.dart';
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/hierarchical/face_filter.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/models/search/hierarchical/only_them_filter.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/ui/components/bottom_action_bar/bottom_action_bar_widget.dart';
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import "package:photos/ui/viewer/gallery/state/boundary_reporter_mixin.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/inherited_search_filter_data.dart";
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class FileSelectionOverlayBar extends StatefulWidget {
  static double roughHeight = Platform.isIOS ? 240.0 : 232.0;
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
  static const Duration animationDuration = Duration(milliseconds: 400);

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
            // iOS pop gesture get's blocked if we do canPop false, so always pop on iOS
            canPop: Platform.isIOS,
            onPopInvokedWithResult: (didPop, _) {
              // for iOS return and don't run anything
              if (didPop) return;

              // Android specific block
              // if nothing is selected then pop the page
              if (widget.selectedFiles.files.isEmpty) {
                Navigator.of(context).pop();
                return;
              }

              // clear all selections if something is selected
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
          firstCurve: Curves.easeInOutExpo,
          secondCurve: Curves.easeInOutExpo,
          sizeCurve: Curves.easeInOutExpo,
          crossFadeState: _hasSelectedFilesNotifier.value
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: _FileSelectionOverlayBarState.animationDuration,
          firstChild: boundaryWidget(
            position: BoundaryPosition.bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: SelectAllButton(
                    backgroundColor: widget.backgroundColor,
                  ),
                ),
                const SizedBox(height: 8),
                BottomActionBarWidget(
                  selectedFiles: widget.selectedFiles,
                  galleryType: _galleryType,
                  collection: widget.collection,
                  person: widget.person,
                  clusterID: widget.clusterID,
                  onCancel: () {
                    if (widget.selectedFiles.files.isNotEmpty) {
                      widget.selectedFiles.clearAll();
                    }
                  },
                  backgroundColor: widget.backgroundColor,
                ),
              ],
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
    // Update boundary after animation completes
    Future.delayed(_FileSelectionOverlayBarState.animationDuration, () {
      final isEmpty = widget.selectedFiles.files.isEmpty;

      // Only report boundary on empty ↔ non-empty transitions
      if (_wasEmpty != isEmpty) {
        // Report boundary - will set to null if widget is not visible
        reportBoundary(BoundaryPosition.bottom);
        _wasEmpty = isEmpty;
      }
    });
  }

  void _filterAppliedListener() {
    widget.selectedFiles.clearAll();
    _updateGalleryTypeIfRequired();
  }

  /// This method is used to update the GalleryType if the initial filter is
  /// removed from the applied filters. As long as the inital filter is present
  /// in the applied filters, the gallery type will remain the same as the type
  /// initally passed in the widget constructor. Once the inital filter is
  /// removed, the gallery type will be updated to GalleryType.searchResults
  /// and never be updated again.
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

class SelectAllButton extends StatefulWidget {
  final Color? backgroundColor;
  const SelectAllButton({super.key, required this.backgroundColor});

  @override
  State<SelectAllButton> createState() => _SelectAllButtonState();
}

class _SelectAllButtonState extends State<SelectAllButton> {
  bool _allSelected = false;
  @override
  Widget build(BuildContext context) {
    final selectionState = SelectionState.of(context);
    final allGalleryFiles = GalleryFilesState.of(context).galleryFilesOrNull;
    if (allGalleryFiles == null) {
      return const SizedBox.shrink();
    }
    assert(
      selectionState != null,
      "SelectionState not found in context, SelectionState should be an ancestor of FileSelectionOverlayBar",
    );
    final colors = components.ComponentTheme.colorsOf(context);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (_allSelected) {
            selectionState.selectedFiles.clearAll();
          } else {
            selectionState.selectedFiles.selectAll(allGalleryFiles.toSet());
          }
          _allSelected = !_allSelected;
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? colors.backgroundBase,
            border: Border.all(color: colors.strokeDark),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).selectAllShort,
                style: components.TextStyles.mini.copyWith(
                  color: colors.textBase,
                ),
              ),
              const SizedBox(width: 4),
              ListenableBuilder(
                listenable: selectionState!.selectedFiles,
                builder: (context, _) {
                  if (selectionState.selectedFiles.files.length ==
                      allGalleryFiles.length) {
                    _allSelected = true;
                  } else {
                    _allSelected = false;
                  }
                  return SelectAllStatusIcon(
                    isSelected: _allSelected,
                    size: 16,
                    unselectedColor: colors.textLighter,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
