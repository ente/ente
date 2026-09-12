import "dart:math";

import "package:ente_components/ente_components.dart" show fillDarkDark;
import "package:ente_strings/ente_strings.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/theme/colors.dart" show strokeFaintDark;
import "package:photos/ui/viewer/file/file_viewer_filmstrip.dart";
import "package:photos/ui/viewer/file/file_viewer_filmstrip_event.dart";
import "package:photos/ui/viewer/file/file_viewer_filmstrip_preview_layer.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

@immutable
class GalleryFileViewerFilmstripLayout {
  static const upperContentGap = 6.0;
  static const compact = GalleryFileViewerFilmstripLayout._(
    FileViewerFilmstripLayout.compact,
  );

  final FileViewerFilmstripLayout filmstrip;

  const GalleryFileViewerFilmstripLayout._(this.filmstrip);

  factory GalleryFileViewerFilmstripLayout.fromMediaQuery(
    MediaQueryData mediaQuery,
  ) {
    final viewPadding = mediaQuery.viewPadding;
    final availableSize = Size(
      max(0.0, mediaQuery.size.width - viewPadding.horizontal),
      max(0.0, mediaQuery.size.height - viewPadding.vertical),
    );
    return GalleryFileViewerFilmstripLayout._(
      FileViewerFilmstripLayout.forAvailableSize(availableSize),
    );
  }

  double get additionalBottomInset => filmstrip.height + upperContentGap;
}

bool shouldShowGalleryFileViewerFilmstrip({
  required bool isEnabled,
  required bool isMinimalistic,
  required bool isGuestView,
  required int itemCount,
}) => isEnabled && !isMinimalistic && !isGuestView && itemCount > 1;

class GalleryFileViewerFilmstripPreviewLayer extends StatelessWidget {
  final List<EnteFile> files;
  final ValueListenable<int?> previewIndex;

  const GalleryFileViewerFilmstripPreviewLayer({
    required this.files,
    required this.previewIndex,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FileViewerFilmstripPreviewLayer(
      previewIndex: previewIndex,
      itemBuilder: (context, index) {
        if (index < 0 || index >= files.length) {
          return const SizedBox.shrink();
        }
        final file = files[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            _GalleryFilmstripThumbnail(file: file, fit: BoxFit.contain),
            if (file.fileType == FileType.video)
              Center(
                child: Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(color: strokeFaintDark, width: 1),
                  ),
                  child: const HugeIcon(
                    icon: HugeIcons.strokeRoundedPlay,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class GalleryFileViewerFilmstripOverlay extends StatelessWidget {
  final List<EnteFile> files;
  final int selectedIndex;
  final double bottomControlsHeight;
  final int? Function(Key key) findChildIndexCallback;
  final ValueListenable<bool> enableFullScreenNotifier;
  final FileViewerFilmstripEventCallback onEvent;
  final GalleryFileViewerFilmstripLayout layout;

  const GalleryFileViewerFilmstripOverlay({
    required this.files,
    required this.selectedIndex,
    required this.bottomControlsHeight,
    required this.findChildIndexCallback,
    required this.enableFullScreenNotifier,
    required this.onEvent,
    required this.layout,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    return Positioned(
      left: safePadding.left,
      right: safePadding.right,
      bottom: safePadding.bottom + bottomControlsHeight,
      height: layout.filmstrip.height,
      child: ValueListenableBuilder<bool>(
        valueListenable: enableFullScreenNotifier,
        builder: (context, isFullScreen, child) => IgnorePointer(
          ignoring: isFullScreen,
          child: AnimatedOpacity(
            opacity: isFullScreen ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: child,
          ),
        ),
        child: FileViewerFilmstrip(
          layout: layout.filmstrip,
          itemCount: files.length,
          selectedIndex: selectedIndex,
          semanticLabel: context.strings.photoViewerFilmstripLabel,
          semanticValueBuilder: (current, total) => context.strings
              .photoViewerFilmstripPosition(current: current, total: total),
          itemKeyBuilder: (index) => ObjectKey(files[index]),
          findChildIndexCallback: findChildIndexCallback,
          itemBuilder: (context, index) {
            final file = files[index];
            return Stack(
              fit: StackFit.expand,
              children: [
                _GalleryFilmstripThumbnail(file: file, fit: BoxFit.cover),
                if (file.fileType == FileType.video)
                  Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 14 * layout.filmstrip.scale,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 3),
                      ],
                    ),
                  ),
              ],
            );
          },
          onEvent: onEvent,
        ),
      ),
    );
  }
}

class _GalleryFilmstripThumbnail extends StatelessWidget {
  final EnteFile file;
  final BoxFit fit;

  const _GalleryFilmstripThumbnail({required this.file, required this.fit});

  @override
  Widget build(BuildContext context) {
    return ThumbnailWidget(
      file,
      key: ObjectKey(file),
      rawThumbnail: true,
      placeholderColor: fillDarkDark,
      diskLoadDeferDuration: galleryThumbnailDiskLoadDeferDuration,
      serverLoadDeferDuration: galleryThumbnailServerLoadDeferDuration,
      shouldShowSyncStatus: false,
      shouldShowFavoriteIcon: false,
      shouldShowVideoOverlayIcon: false,
      shouldShowLivePhotoOverlay: false,
      fit: fit,
    );
  }
}
