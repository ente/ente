import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/material.dart";
import "package:flutter_animate/flutter_animate.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/db/files_db.dart";
import 'package:photos/models/collection/collection.dart';
import "package:photos/models/selected_files.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/filter/db_filters.dart";
import "package:photos/ui/actions/collection/collection_file_actions.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/components/bottom_action_bar/action_bar_widget.dart";
import "package:photos/ui/device_picker/device_picker_page.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/boundary_reporter_mixin.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";

Future<dynamic> showAddPhotosSheet(
  BuildContext context,
  Collection collection,
) async {
  return await showBottomSheetComponent<dynamic>(
    context: context,
    builder: (context) {
      return LayoutBuilder(
        builder: (context, _) => FractionallySizedBox(
          heightFactor: _sheetHeightFactor,
          alignment: Alignment.bottomCenter,
          child: GalleryBoundariesProvider(
            child: AddPhotosPhotoWidget(collection),
          ),
        ),
      );
    },
    enableDrag: false,
  );
}

const double _sheetHeightFactor = 0.98;

class AddPhotosPhotoWidget extends StatefulWidget {
  final Collection collection;

  const AddPhotosPhotoWidget(this.collection, {super.key});

  @override
  State<AddPhotosPhotoWidget> createState() => _AddPhotosPhotoWidgetState();
}

class _AddPhotosPhotoWidgetState extends State<AddPhotosPhotoWidget> {
  final _selectedFiles = SelectedFiles();

  @override
  void dispose() {
    _selectedFiles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Set<int> hiddenCollectionIDs = CollectionsService.instance
        .getHiddenCollectionIds();
    hiddenCollectionIDs.add(widget.collection.id);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.componentColors.backgroundBase,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(Radii.bottomSheet),
          topRight: Radius.circular(Radii.bottomSheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetBoundary(
              position: BoundaryPosition.top,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.xl,
                  Spacing.xl,
                  Spacing.xl,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.strings.addMore,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.h2.copyWith(
                          color: context.componentColors.textBase,
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    IconButtonComponent(
                      tooltip: context.strings.close,
                      variant: IconButtonComponentVariant.circular,
                      shouldSurfaceExecutionStates: false,
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedCancel01,
                        size: IconSizes.small,
                      ),
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DelayedGallery(
                    hiddenCollectionIDs: hiddenCollectionIDs,
                    selectedFiles: _selectedFiles,
                  ),
                  PositionedDirectional(
                    start: Spacing.lg,
                    end: Spacing.lg,
                    bottom: Spacing.md,
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: ListenableBuilder(
                        listenable: _selectedFiles,
                        builder: (context, _) => _selectedFiles.files.isEmpty
                            ? const SizedBox.shrink()
                            : ActionBarWidget(
                                selectedFiles: _selectedFiles,
                                onCancel: () => _selectedFiles.clearAll(),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: _selectedFiles,
              builder: (context, _) {
                final isFileSelected = _selectedFiles.files.isNotEmpty;
                return _SheetBoundary(
                  position: BoundaryPosition.bottom,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 428),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.xl,
                          Spacing.lg,
                          Spacing.xl,
                          Spacing.sm,
                        ),
                        child: Column(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              switchInCurve: Curves.easeInOutExpo,
                              switchOutCurve: Curves.easeInOutExpo,
                              child: ButtonComponent(
                                key: ValueKey(isFileSelected),
                                variant: ButtonComponentVariant.primary,
                                isDisabled: !isFileSelected,
                                label: context.strings.addSelected,
                                onTap: () async {
                                  final selectedFile = _selectedFiles.files;
                                  final ca = CollectionActions(
                                    CollectionsService.instance,
                                  );
                                  await ca.addToCollection(
                                    context,
                                    widget.collection.id,
                                    false,
                                    selectedFiles: selectedFile.toList(),
                                  );
                                  if (!context.mounted) return;
                                  Navigator.pop(context, selectedFile);
                                },
                              ),
                            ),
                            const SizedBox(height: Spacing.md),
                            ButtonComponent(
                              variant: ButtonComponentVariant.secondary,
                              label: context.strings.addFromDevice,
                              onTap: () async {
                                await _onPickFromDeviceClicked(context);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onPickFromDeviceClicked(BuildContext context) async {
    final result = await showDevicePicker(context);
    if (!context.mounted || result == null || result.isEmpty) return;
    final added = await CollectionActions(CollectionsService.instance)
        .addToCollection(
          context,
          widget.collection.id,
          false,
          picketAssets: result,
        );
    if (context.mounted && added) Navigator.of(context).pop();
  }
}

class DelayedGallery extends StatefulWidget {
  const DelayedGallery({
    super.key,
    required this.hiddenCollectionIDs,
    required this.selectedFiles,
  });

  final Set<int> hiddenCollectionIDs;
  final SelectedFiles selectedFiles;

  @override
  State<DelayedGallery> createState() => _DelayedGalleryState();
}

class _DelayedGalleryState extends State<DelayedGallery> {
  bool _showGallery = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _showGallery = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showGallery) {
      return GalleryFilesState(
        child:
            Gallery(
              inSelectionMode: true,
              asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) {
                return FilesDB.instance.getAllPendingOrUploadedFiles(
                  creationStartTime,
                  creationEndTime,
                  Configuration.instance.getUserID()!,
                  limit: limit,
                  asc: asc,
                  filterOptions: DBFilterOptions(
                    hideIgnoredForUpload: true,
                    dedupeUploadID: true,
                    ignoredCollectionIDs: widget.hiddenCollectionIDs,
                  ),
                  applyOwnerCheck: true,
                );
              },
              tagPrefix: "pick_add_photos_gallery",
              selectedFiles: widget.selectedFiles,
              footer: ListenableBuilder(
                listenable: widget.selectedFiles,
                builder: (context, _) => SizedBox(
                  height: widget.selectedFiles.files.isEmpty
                      ? 0
                      : MediaQuery.textScalerOf(context).scale(kToolbarHeight),
                ),
              ),
              showSelectAll: true,
              sortAsyncFn: () => false,
              disablePinnedGroupHeader: true,
              disableVerticalPaddingForScrollbar: true,
            ).animate().fadeIn(
              duration: const Duration(milliseconds: 175),
              curve: Curves.easeOutCirc,
            ),
      );
    } else {
      return const EnteLoadingWidget();
    }
  }
}

class _SheetBoundary extends StatefulWidget {
  final BoundaryPosition position;
  final Widget child;

  const _SheetBoundary({required this.position, required this.child});

  @override
  State<_SheetBoundary> createState() => _SheetBoundaryState();
}

class _SheetBoundaryState extends State<_SheetBoundary> with BoundaryReporter {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation,
      builder: (context, child) =>
          boundaryWidget(position: widget.position, child: child!),
      child: widget.child,
    );
  }
}
