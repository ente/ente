import 'package:flutter/material.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/collection_meta_event.dart';
import 'package:photos/events/collection_updated_event.dart';
import 'package:photos/events/files_updated_event.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import 'package:photos/models/file_load_result.dart';
import 'package:photos/models/gallery_type.dart';
import 'package:photos/models/selected_files.dart';
import "package:photos/services/search_service.dart";
import "package:photos/theme/ente_theme.dart";
import 'package:photos/ui/viewer/actions/file_selection_overlay_bar.dart';
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import 'package:photos/ui/viewer/gallery/gallery.dart';
import "package:photos/ui/viewer/gallery/state/boundary_reporter_mixin.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

enum LargeFileFilter { all, photos, videos }

class LargeFilesPagePage extends StatefulWidget {
  final String tagPrefix;
  final GalleryType appBarType;
  final GalleryType overlayType;
  final _selectedFiles = SelectedFiles();
  static const int minLargeFileSize = 10 * 1024 * 1024;

  LargeFilesPagePage({
    this.tagPrefix = "Uncategorized_page",
    this.appBarType = GalleryType.homepage,
    this.overlayType = GalleryType.homepage,
    super.key,
  });

  @override
  State<LargeFilesPagePage> createState() => _LargeFilesPagePageState();
}

class _LargeFilesPagePageState extends State<LargeFilesPagePage> {
  LargeFileFilter _currentFilter = LargeFileFilter.all;

  bool _matchesFilter(EnteFile file) {
    switch (_currentFilter) {
      case LargeFileFilter.all:
        return true;
      case LargeFileFilter.photos:
        return file.fileType == FileType.image ||
            file.fileType == FileType.livePhoto;
      case LargeFileFilter.videos:
        return file.fileType == FileType.video;
    }
  }

  void _onFilterChanged(LargeFileFilter filter) {
    if (_currentFilter != filter) {
      setState(() {
        _currentFilter = filter;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gallery = Gallery(
      key: ValueKey(_currentFilter),
      asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) async {
        final List<EnteFile> allFiles = await SearchService.instance
            .getAllFilesForSearch();
        final Set<int> alreadyTracked = <int>{};

        final filesWithSize = <EnteFile>[];
        for (final file in allFiles) {
          if (file.isOwner &&
              file.isUploaded &&
              file.fileSize != null &&
              file.fileSize! > LargeFilesPagePage.minLargeFileSize &&
              _matchesFilter(file)) {
            if (!alreadyTracked.contains(file.uploadedFileID!)) {
              filesWithSize.add(file);
              alreadyTracked.add(file.uploadedFileID!);
            }
          }
        }
        // sort by file size descending
        filesWithSize.sort((a, b) => b.fileSize!.compareTo(a.fileSize!));
        final FileLoadResult result = FileLoadResult(filesWithSize, false);
        return result;
      },
      reloadEvent: Bus.instance.on<CollectionUpdatedEvent>(),
      removalEventTypes: const {
        EventType.deletedFromRemote,
        EventType.deletedFromEverywhere,
        EventType.hide,
      },
      forceReloadEvents: [Bus.instance.on<CollectionMetaEvent>()],
      tagPrefix: widget.tagPrefix,
      selectedFiles: widget._selectedFiles,
      sortAsyncFn: () => false,
      groupType: GroupType.size,
      initialFiles: null,
      albumName: AppLocalizations.of(context).viewLargeFiles,
    );
    return GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(100.0),
            child: _LargeFilesAppBar(
              currentFilter: _currentFilter,
              onFilterChanged: _onFilterChanged,
            ),
          ),
          body: SelectionState(
            selectedFiles: widget._selectedFiles,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                gallery,
                FileSelectionOverlayBar(
                  widget.overlayType,
                  widget._selectedFiles,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LargeFilesAppBar extends StatefulWidget {
  final LargeFileFilter currentFilter;
  final ValueChanged<LargeFileFilter> onFilterChanged;

  const _LargeFilesAppBar({
    required this.currentFilter,
    required this.onFilterChanged,
  });

  @override
  State<_LargeFilesAppBar> createState() => _LargeFilesAppBarState();
}

class _LargeFilesAppBarState extends State<_LargeFilesAppBar>
    with BoundaryReporter {
  @override
  Widget build(BuildContext context) {
    return boundaryWidget(
      position: BoundaryPosition.top,
      child: AppBar(
        elevation: 0,
        centerTitle: false,
        title: Text(
          AppLocalizations.of(context).viewLargeFiles,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall!.copyWith(fontSize: 16),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50.0),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Row(
              children: [
                _FilterChip(
                  label: AppLocalizations.of(context).all,
                  isSelected: widget.currentFilter == LargeFileFilter.all,
                  onTap: () => widget.onFilterChanged(LargeFileFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: AppLocalizations.of(context).photos,
                  icon: Icons.image,
                  isSelected: widget.currentFilter == LargeFileFilter.photos,
                  onTap: () => widget.onFilterChanged(LargeFileFilter.photos),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: AppLocalizations.of(context).videos,
                  icon: Icons.videocam,
                  isSelected: widget.currentFilter == LargeFileFilter.videos,
                  onTap: () => widget.onFilterChanged(LargeFileFilter.videos),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary500 : colorScheme.fillFaint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary500
                : colorScheme.strokeFaint,
            width: 0.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? colorScheme.backgroundColour
                      : colorScheme.textBase,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: textTheme.miniBold.copyWith(
                  color: isSelected
                      ? colorScheme.backgroundColour
                      : colorScheme.textBase,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
