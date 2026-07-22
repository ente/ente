import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/user_config.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/viewer/file_details/file_info_faces_item_widget.dart";
import "package:photos/ui/viewer/file_details/file_info_pets_item_widget.dart";
import "package:photos/ui/viewer/file_details_new/added_by_widget.dart";
import "package:photos/ui/viewer/file_details_new/albums_item_widget.dart";
import "package:photos/ui/viewer/file_details_new/creation_time_item_widget.dart";
import "package:photos/ui/viewer/file_details_new/exif_item_widgets.dart";
import "package:photos/ui/viewer/file_details_new/file_caption_widget.dart";
import "package:photos/ui/viewer/file_details_new/file_details_menu_group.dart";
import "package:photos/ui/viewer/file_details_new/file_details_metadata_controller.dart";
import "package:photos/ui/viewer/file_details_new/file_details_skeleton.dart";
import "package:photos/ui/viewer/file_details_new/file_properties_item_widget.dart";
import "package:photos/ui/viewer/file_details_new/location_tags_widget.dart";
import "package:photos/ui/viewer/file_details_new/preview_properties_item_widget.dart";
import "package:photos/ui/viewer/file_details_new/video_exif_item.dart";

/// Parallel file-details implementation used by the Android details sheet.
class FileDetailsNewWidget extends StatefulWidget {
  const FileDetailsNewWidget(
    this.file, {
    required this.scrollController,
    super.key,
  });

  final EnteFile file;
  final ScrollController scrollController;

  @override
  State<FileDetailsNewWidget> createState() => _FileDetailsNewWidgetState();
}

class _FileDetailsNewWidgetState extends State<FileDetailsNewWidget> {
  static const _metadataDelay = Duration(milliseconds: 350);
  static const _videoMetadataDelay = Duration(milliseconds: 650);

  late final FileDetailsMetadataController _metadata;
  late final int _currentUserID;
  Timer? _metadataTimer;

  @override
  void initState() {
    super.initState();
    _currentUserID = Configuration.instance.getUserIDV2();
    _metadata = FileDetailsMetadataController(
      file: widget.file,
      currentUserID: _currentUserID,
    );
    if (widget.file.fileType == FileType.image ||
        widget.file.fileType == FileType.livePhoto) {
      _metadataTimer = Timer(_metadataDelay, _metadata.loadExif);
    } else if (widget.file.isVideo && flagService.internalUser) {
      _metadataTimer = Timer(_videoMetadataDelay, _metadata.loadVideo);
    }
  }

  @override
  void dispose() {
    _metadataTimer?.cancel();
    _metadata.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final isImage =
        file.fileType == FileType.image || file.fileType == FileType.livePhoto;
    final canEditCaption =
        (file.ownerID == null || file.ownerID == _currentUserID) &&
        !file.isTrash;
    final internalUser = file.isVideo && flagService.internalUser;
    final hasPreview =
        file.uploadedFileID != null &&
        fileDataService.previewIds.containsKey(file.uploadedFileID);
    final sections = <WidgetBuilder>[
      (_) => AddedByWidgetNew(file),
      if (file.isUploaded &&
          (canEditCaption || (file.caption?.isNotEmpty ?? false)))
        (context) => Padding(
          padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.xl),
          child: canEditCaption
              ? FileCaptionWidgetNew(file: file)
              : Text(
                  file.caption!,
                  style: TextStyles.body.copyWith(
                    color: context.componentColors.textLight,
                  ),
                ),
        ),
      (_) => _SpacedSection(
        child: ValueListenableBuilder(
          valueListenable: _metadata.exifDetails,
          child: CreationTimeItemNew(file, _currentUserID),
          builder: (context, exif, creationTimeItem) => FileDetailsAnimatedSize(
            child: FileDetailsMenuGroupNew(
              items: [
                creationTimeItem!,
                FilePropertiesItemWidgetNew(
                  file: file,
                  isImage: isImage,
                  currentUserID: _currentUserID,
                  loadDelay: _metadataDelay + const Duration(milliseconds: 300),
                  exifDetails: _metadata.exifDetails,
                ),
                if (isImage)
                  if (exif == null)
                    const FileDetailsSectionSkeleton(
                      kind: FileDetailsSkeletonKind.menuRow,
                      height: fileDetailsMenuRowHeight,
                    )
                  else if (exif.hasBasicData)
                    BasicExifItemWidgetNew(exif),
              ],
            ),
          ),
        ),
      ),
      if (hasGrantedMLConsent)
        (_) => _SpacedSection(
          child: FileDetailsAnimatedSize(child: FacesItemWidget(file)),
        ),
      if (hasGrantedMLConsent &&
          flagService.petEnabled &&
          localSettings.petRecognitionEnabled)
        (_) => _SpacedSection(
          child: FileDetailsAnimatedSize(child: PetsItemWidget(file)),
        ),
      if (file.hasLocation || isImage || internalUser)
        (_) => ValueListenableBuilder(
          valueListenable: _metadata.hasLocation,
          builder: (context, hasLocation, _) => hasLocation
              ? _SpacedSection(
                  child: LocationTagsWidgetNew(
                    file: file,
                    mapLoadDelay:
                        _metadataDelay + const Duration(milliseconds: 150),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      if (!file.isTrash)
        (_) => _SpacedSection(
          child: AlbumsItemWidgetNew(
            file: file,
            loadDelay: _metadataDelay + const Duration(milliseconds: 200),
          ),
        ),
      if (isImage || (file.isVideo && (hasPreview || internalUser)))
        (_) => _MediaMetadataSectionNew(
          file: file,
          hasPreview: hasPreview,
          metadata: _metadata,
        ),
    ];
    return SafeArea(
      top: false,
      child: Scrollbar(
        controller: widget.scrollController,
        thickness: 4,
        radius: const Radius.circular(2),
        thumbVisibility: true,
        child: CustomScrollView(
          controller: widget.scrollController,
          physics: const ClampingScrollPhysics(),
          slivers: [
            const _FileDetailsHeaderNew(),
            const SliverToBoxAdapter(child: SizedBox(height: Spacing.lg)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.xl,
                0,
                Spacing.xl,
                Spacing.xl,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => sections[index](context),
                  childCount: sections.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpacedSection extends StatelessWidget {
  const _SpacedSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Spacing.xxl),
    child: child,
  );
}

class _MediaMetadataSectionNew extends StatefulWidget {
  const _MediaMetadataSectionNew({
    required this.file,
    required this.hasPreview,
    required this.metadata,
  });

  final EnteFile file;
  final bool hasPreview;
  final FileDetailsMetadataController metadata;

  @override
  State<_MediaMetadataSectionNew> createState() =>
      _MediaMetadataSectionNewState();
}

class _MediaMetadataSectionNewState extends State<_MediaMetadataSectionNew> {
  static const _loadDelay = Duration(milliseconds: 650);

  @override
  Widget build(BuildContext context) {
    final isImage =
        widget.file.fileType == FileType.image ||
        widget.file.fileType == FileType.livePhoto;
    final showVideoMetadata = widget.file.isVideo && flagService.internalUser;
    return _SpacedSection(
      child: FileDetailsMenuGroupNew(
        items: [
          if (widget.hasPreview)
            PreviewPropertiesItemWidgetNew(
              file: widget.file,
              loadDelay: _loadDelay,
            ),
          if (isImage)
            ValueListenableBuilder(
              valueListenable: widget.metadata.exifTags,
              builder: (context, exif, _) =>
                  AllExifItemWidgetNew(widget.file, exif),
            )
          else if (showVideoMetadata)
            ValueListenableBuilder(
              valueListenable: widget.metadata.videoMetadata,
              builder: (context, metadata, _) => VideoExifRowItemNew(metadata),
            ),
        ],
      ),
    );
  }
}

class _FileDetailsHeaderNew extends StatelessWidget {
  const _FileDetailsHeaderNew();

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      automaticallyImplyLeading: false,
      backgroundColor: context.componentColors.backgroundBase,
      surfaceTintColor: Colors.transparent,
      primary: false,
      pinned: true,
      centerTitle: false,
      toolbarHeight: 38 + Spacing.xl,
      titleSpacing: Spacing.xl,
      title: Text(
        AppLocalizations.of(context).details,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyles.h2.copyWith(color: context.componentColors.textBase),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: Spacing.xl),
          child: IconButtonComponent(
            tooltip: AppLocalizations.of(context).close,
            variant: IconButtonComponentVariant.circular,
            shouldSurfaceExecutionStates: false,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedCancel01,
              size: IconSizes.small,
            ),
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
