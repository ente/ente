import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:media_extension/media_extension.dart";
import "package:media_extension/media_extension_action_types.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/file_uploaded_event.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/gallery_type.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/services/app_lifecycle_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/touch_cross_detector.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/gallery/component/swipe_selectable_file_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_context_state.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_swipe_helper.dart";
import "package:photos/utils/file_util.dart";

class GalleryFileWidget extends StatefulWidget {
  final EnteFile file;
  final SelectedFiles? selectedFiles;
  final bool limitSelectionToOne;
  final String tag;
  final int photoGridSize;
  final int? currentUserID;
  const GalleryFileWidget({
    required this.file,
    required this.selectedFiles,
    required this.limitSelectionToOne,
    required this.tag,
    required this.photoGridSize,
    required this.currentUserID,
    super.key,
  });

  @override
  State<GalleryFileWidget> createState() => _GalleryFileWidgetState();
}

class _GalleryFileWidgetState extends State<GalleryFileWidget> {
  static const borderRadius = BorderRadius.all(Radius.circular(1));
  static final _logger = Logger("GalleryFileWidget");
  late bool _isFileSelected;
  int? _currentPointerId;
  bool _isPointerInside = false;
  late final StreamSubscription<FileUploadedEvent> _fileUploadedSubscription;

  @override
  void initState() {
    super.initState();
    _isFileSelected =
        widget.selectedFiles?.isFileSelected(widget.file) ?? false;
    widget.selectedFiles?.addListener(_selectedFilesListener);
    _fileUploadedSubscription = Bus.instance.on<FileUploadedEvent>().listen((
      event,
    ) {
      if (event.file.generatedID != null &&
          event.file.generatedID == widget.file.generatedID &&
          mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _fileUploadedSubscription.cancel();
    widget.selectedFiles?.removeListener(_selectedFilesListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget fileContent = _buildFileContent(context);

    if (!widget.limitSelectionToOne) {
      return SwipeSelectableFileWidget(
        file: widget.file,
        selectedFiles: widget.selectedFiles,
        onPointerStateChanged: (pointerId, isInside) {
          _currentPointerId = pointerId ?? _currentPointerId;
          _isPointerInside = isInside;
          if (pointerId == null) {
            _currentPointerId = null;
          }
        },
        child: fileContent,
      );
    }

    return fileContent;
  }

  Widget _buildFileContent(BuildContext context) {
    Color selectionColor = Colors.white;
    if (_isFileSelected &&
        widget.file.isUploaded &&
        widget.file.ownerID != null &&
        widget.file.ownerID != widget.currentUserID) {
      final avatarColors = getEnteColorScheme(context).avatarColors;
      selectionColor =
          avatarColors[widget.file.ownerID!.remainder(avatarColors.length)];
    }
    final String heroTag = widget.tag + widget.file.tag;
    final Widget thumbnailWidget = ThumbnailWidget(
      widget.file,
      diskLoadDeferDuration: galleryThumbnailDiskLoadDeferDuration,
      serverLoadDeferDuration: galleryThumbnailServerLoadDeferDuration,
      shouldShowLivePhotoOverlay: true,
      key: Key(heroTag),
      thumbnailSize: widget.photoGridSize < photoGridSizeDefault
          ? thumbnailLargeSize
          : thumbnailSmallSize,
      shouldShowOwnerAvatar: !_isFileSelected,
      ownerAvatarType: widget.photoGridSize < photoGridSizeMax
          ? AvatarType.small
          : AvatarType.xs,
      shouldShowVideoDuration: true,
    );
    return GestureDetector(
      onTap: () {
        widget.limitSelectionToOne
            ? _onTapWithSelectionLimit(widget.file)
            : _onTapNoSelectionLimit(context, widget.file);
      },
      onLongPress: () {
        widget.limitSelectionToOne
            ? _onLongPressWithSelectionLimit(context, widget.file)
            : _onLongPressNoSelectionLimit(context, widget.file);
      },
      child: _isFileSelected
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  key: ValueKey(heroTag),
                  borderRadius: borderRadius,
                  child: Hero(
                    tag: heroTag,
                    flightShuttleBuilder:
                        (
                          flightContext,
                          animation,
                          flightDirection,
                          fromHeroContext,
                          toHeroContext,
                        ) => (toHeroContext.widget as Hero).child,
                    transitionOnUserGestures: true,
                    child: ClipRRect(
                      borderRadius: borderRadius,
                      child: thumbnailWidget,
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: Color.fromARGB(102, 0, 0, 0),
                    borderRadius: borderRadius,
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: SelectAllStatusIcon(
                    isSelected: true,
                    size: 16,
                    selectedFillColor: selectionColor, //same for both themes
                    selectedTickCutsOut: true,
                  ),
                ),
              ],
            )
          : ClipRRect(
              key: ValueKey(heroTag),
              borderRadius: borderRadius,
              child: Hero(
                tag: heroTag,
                flightShuttleBuilder:
                    (
                      flightContext,
                      animation,
                      flightDirection,
                      fromHeroContext,
                      toHeroContext,
                    ) => (toHeroContext.widget as Hero).child,
                transitionOnUserGestures: true,
                child: ClipRRect(
                  borderRadius: borderRadius,
                  child: thumbnailWidget,
                ),
              ),
            ),
    );
  }

  void _selectedFilesListener() {
    late bool latestSelectionState;
    if (widget.selectedFiles?.files.contains(widget.file) ?? false) {
      latestSelectionState = true;
    } else {
      latestSelectionState = false;
    }
    if (latestSelectionState != _isFileSelected && mounted) {
      setState(() {
        _isFileSelected = latestSelectionState;
      });
    }
  }

  void _toggleFileSelection(EnteFile file) {
    HapticFeedback.selectionClick();
    widget.selectedFiles!.toggleSelection(file);
  }

  void _onTapWithSelectionLimit(EnteFile file) {
    if (widget.selectedFiles!.files.isNotEmpty &&
        widget.selectedFiles!.files.first != file) {
      widget.selectedFiles!.clearAll();
    }
    _toggleFileSelection(file);
  }

  void _onTapNoSelectionLimit(BuildContext context, EnteFile file) async {
    final bool shouldToggleSelection =
        (widget.selectedFiles?.files.isNotEmpty ?? false) ||
        (GalleryContextState.of(context)?.inSelectionMode ?? false);
    if (shouldToggleSelection) {
      if (widget.selectedFiles == null) {
        return;
      }
      _toggleFileSelection(file);
    } else {
      if (AppLifecycleService.instance.mediaExtensionAction.action ==
          IntentAction.pick) {
        final ioFile = await getFile(file);
        await MediaExtension().setResult("file://${ioFile!.path}");
      } else {
        _routeToDetailPage(file, context);
      }
    }
  }

  void _onLongPressNoSelectionLimit(BuildContext context, EnteFile file) {
    final selectedFiles = widget.selectedFiles;
    if (selectedFiles == null || selectedFiles.files.isNotEmpty) {
      _routeToDetailPage(file, context);
    } else {
      _toggleFileSelection(file);
      // Notify SwipeSelectableFileWidget if it exists
      _handleLongPressForSwipe();
    }
  }

  void _handleLongPressForSwipe() {
    // Use local state to determine if swipe should start
    final swipeHelper = GallerySwipeHelper.of(context);
    if (_currentPointerId != null &&
        _isPointerInside &&
        TouchCrossDetector.isPointerActive(_currentPointerId!) &&
        swipeHelper != null &&
        widget.selectedFiles != null &&
        widget.selectedFiles!.files.isNotEmpty) {
      swipeHelper.startSelection(widget.file, forceSelecting: true);
    }
  }

  Future<void> _onLongPressWithSelectionLimit(
    BuildContext context,
    EnteFile file,
  ) async {
    if (AppLifecycleService.instance.mediaExtensionAction.action ==
        IntentAction.pick) {
      final ioFile = await getFile(file);
      await MediaExtension().setResult("file://${ioFile!.path}");
    } else {
      _routeToDetailPage(file, context);
    }
  }

  void _routeToDetailPage(EnteFile file, BuildContext context) {
    final galleryFiles = GalleryFilesState.of(context).galleryFiles;
    final selectedIndex = galleryFiles.indexOf(file);
    // A refresh can make the tapped tile stale.
    if (selectedIndex < 0) {
      _logger.warning(
        "Not opening viewer; tapped item is no longer in the gallery",
      );
      return;
    }
    // Device folders (local-only contexts) should keep files visible
    // even after deleting from Ente (remote) since they still exist locally
    final galleryType = GalleryContextState.of(context)?.galleryType;
    final isLocalOnlyContext = galleryType == GalleryType.localFolder;
    final page = DetailPage(
      DetailPageConfiguration(
        galleryFiles,
        selectedIndex,
        widget.tag,
        isLocalOnlyContext: isLocalOnlyContext,
        galleryType: galleryType,
      ),
    );
    routeToPage(context, page, forceCustomPageRoute: true);
  }
}
