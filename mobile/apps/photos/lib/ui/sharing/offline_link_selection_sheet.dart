import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";

class OfflineLinkSelectionSheet extends StatelessWidget {
  const OfflineLinkSelectionSheet({
    super.key,
    required this.files,
    this.onCreateLink,
  });
  final List<EnteFile> files;
  final Future<void> Function(List<EnteFile>)? onCreateLink;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.86,
    alignment: Alignment.bottomCenter,
    child: GalleryBoundariesProvider(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.componentColors.backgroundBase,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.bottomSheet),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SelectionHeader(),
              const SizedBox(height: Spacing.lg),
              Expanded(
                child: GalleryFilesState(
                  child: Gallery(
                    initialFiles: files,
                    asyncLoader: (_, _, {limit, asc}) async =>
                        FileLoadResult(files, false),
                    tagPrefix: "offline_link_selection",
                    enableFileGrouping: false,
                    showSelectAll: false,
                    disablePinnedGroupHeader: true,
                    disableVerticalPaddingForScrollbar: true,
                    footer: const SizedBox.shrink(),
                    emptyState: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(Spacing.xl),
                        child: Text(
                          pendingTranslation(
                            "No selected files are available on this device.",
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 428),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.xl,
                      Spacing.lg,
                      Spacing.xl,
                      Spacing.sm,
                    ),
                    child: ButtonComponent(
                      key: const ValueKey("offline-link-create-option"),
                      label: pendingTranslation("Create link"),
                      shouldSurfaceExecutionStates: false,
                      leading: const HugeIcon(
                        icon: HugeIcons.strokeRoundedLink02,
                        size: IconSizes.small,
                      ),
                      isDisabled: files.isEmpty,
                      // Remains disabled until real link creation is wired.
                      onTap: onCreateLink == null
                          ? null
                          : () => onCreateLink!(files),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.xl, Spacing.xl, 0),
    child: Row(
      children: [
        Expanded(
          child: Text(
            pendingTranslation("Share link"),
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
  );
}
