import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/collection_updated_event.dart";
import 'package:photos/models/collection/collection.dart';
import "package:photos/models/file_load_result.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/services/ignored_files_service.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";

Future<int?> showPickCoverPhotoSheet(
  BuildContext context,
  Collection collection, {
  required bool hasEffectiveCustomCover,
}) {
  return showBottomSheetComponent<int>(
    context: context,
    builder: (_) => PickCoverPhotoWidget(
      collection,
      hasEffectiveCustomCover: hasEffectiveCustomCover,
    ),
    enableDrag: true,
  );
}

class PickCoverPhotoWidget extends StatefulWidget {
  final Collection collection;
  final bool hasEffectiveCustomCover;

  const PickCoverPhotoWidget(
    this.collection, {
    super.key,
    required this.hasEffectiveCustomCover,
  });

  @override
  State<PickCoverPhotoWidget> createState() => _PickCoverPhotoWidgetState();
}

class _PickCoverPhotoWidgetState extends State<PickCoverPhotoWidget> {
  late final SelectedFiles _selectedFiles;

  @override
  void initState() {
    super.initState();
    _selectedFiles = SelectedFiles()..addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _selectedFiles.dispose();
    super.dispose();
  }

  void _onSelectionChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    final hasSelection = _selectedFiles.files.isNotEmpty;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height,
      child: BottomSheetComponent(
        header: const _PickCoverPhotoHeader(),
        showCloseButton: false,
        padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
        content: Expanded(
          child: GalleryFilesState(
            child: Gallery(
              asyncLoader:
                  (creationStartTime, creationEndTime, {limit, asc}) async {
                    final FileLoadResult result = await FilesDB.instance
                        .getFilesInCollection(
                          widget.collection.id,
                          creationStartTime,
                          creationEndTime,
                          limit: limit,
                          asc: asc,
                        );
                    final ignoredIDs =
                        await IgnoredFilesService.instance.idToIgnoreReasonMap;
                    result.files.removeWhere(
                      (file) =>
                          file.uploadedFileID == null &&
                          IgnoredFilesService.instance.shouldSkipUpload(
                            ignoredIDs,
                            file,
                          ),
                    );
                    return result;
                  },
              reloadEvent: Bus.instance.on<CollectionUpdatedEvent>().where(
                (event) => event.collectionID == widget.collection.id,
              ),
              tagPrefix: "pick_cover_photo_gallery",
              selectedFiles: _selectedFiles,
              limitSelectionToOne: true,
              showSelectAll: false,
              sortAsyncFn: () =>
                  widget.collection.pubMagicMetadata.asc ?? false,
              disablePinnedGroupHeader: true,
              disableVerticalPaddingForScrollbar: true,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ButtonComponent(
                  isDisabled: !hasSelection,
                  label: l10n.useSelectedPhoto,
                  density: ButtonComponentDensity.compact,
                  shouldSurfaceExecutionStates: false,
                  onTap: hasSelection
                      ? () {
                          Navigator.pop(
                            context,
                            _selectedFiles.files.first.uploadedFileID!,
                          );
                        }
                      : null,
                ),
                if (widget.hasEffectiveCustomCover) ...[
                  const SizedBox(height: Spacing.md),
                  ButtonComponent(
                    variant: ButtonComponentVariant.secondary,
                    label: l10n.resetToDefault,
                    density: ButtonComponentDensity.compact,
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedRefresh,
                      size: IconSizes.small,
                    ),
                    shouldSurfaceExecutionStates: false,
                    onTap: () => Navigator.pop(context, 0),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickCoverPhotoHeader extends StatelessWidget {
  const _PickCoverPhotoHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    final colors = context.componentColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.selectCoverPhoto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyles.h1Bold.copyWith(color: colors.textBase),
              ),
            ),
            const SizedBox(width: Spacing.md),
            IconButtonComponent(
              tooltip: l10n.close,
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
    );
  }
}
