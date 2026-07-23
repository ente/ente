import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:photos/core/constants.dart";
import "package:photos/db/files_db.dart";
import "package:photos/models/file/file.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

/// Displays a grid of shared photos with different layouts based on count.
///
/// Layouts:
/// - 1 photo: Full width, aspect ratio based on image
/// - 2 photos: Vertical stack (two rows)
/// - 3 photos: 2 on top, 1 on bottom spanning full width
/// - 4+ photos: 2x2 grid with "+N" overlay on last cell if more than 4
class SharedPhotosGrid extends StatefulWidget {
  /// List of file IDs to display.
  final List<int> fileIDs;

  /// Collection ID for loading files.
  final int collectionID;

  /// Called when user taps on the grid.
  final VoidCallback? onTap;

  /// Called when user taps an individual photo thumbnail.
  final ValueChanged<int>? onPhotoTap;

  /// Called when user taps the +N extra-count badge.
  final VoidCallback? onExtraCountTap;

  /// Prefix used for Hero tags while opening shared photos.
  final String heroTagPrefix;

  /// Size of the grid (width). Height is calculated based on layout.
  final double gridSize;

  const SharedPhotosGrid({
    required this.fileIDs,
    required this.collectionID,
    required this.heroTagPrefix,
    this.onTap,
    this.onPhotoTap,
    this.onExtraCountTap,
    this.gridSize = 300,
    super.key,
  });

  @override
  State<SharedPhotosGrid> createState() => _SharedPhotosGridState();
}

class _SharedPhotosGridState extends State<SharedPhotosGrid> {
  List<EnteFile?> _files = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void didUpdateWidget(SharedPhotosGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.fileIDs, widget.fileIDs) ||
        oldWidget.collectionID != widget.collectionID) {
      _loadFiles();
    }
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);

    // Load up to 4 files for display using batch query
    final filesToLoad = widget.fileIDs.take(4).toList();
    final files = await FilesDB.instance.getUploadedFilesBatch(
      filesToLoad,
      widget.collectionID,
    );

    if (mounted) {
      setState(() {
        _files = files;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    if (_isLoading) {
      return Container(
        width: widget.gridSize,
        height: widget.gridSize,
        decoration: BoxDecoration(
          color: colorScheme.fillFaint,
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    final validFiles = _files.whereType<EnteFile>().toList();
    if (validFiles.isEmpty) {
      return Container(
        width: widget.gridSize,
        height: widget.gridSize,
        decoration: BoxDecoration(
          color: colorScheme.fillFaint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.photo_library_outlined,
          color: colorScheme.strokeMuted,
          size: 48,
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: colorScheme.strokeFaint),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: widget.gridSize,
            height: widget.gridSize,
            child: _buildGrid(validFiles),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(List<EnteFile> files) {
    final count = files.length;
    final totalCount = widget.fileIDs.length;
    final extraCount = totalCount - 4;

    switch (count) {
      case 1:
        return _buildSinglePhoto(files[0]);
      case 2:
        return _buildTwoPhotos(files);
      case 3:
        return _buildThreePhotos(files);
      default:
        return _buildFourPlusPhotos(files, extraCount);
    }
  }

  Widget _buildSinglePhoto(EnteFile file) {
    return _buildSharedPhotoThumbnail(file);
  }

  Widget _buildTwoPhotos(List<EnteFile> files) {
    const gap = 2.0;
    final itemHeight = (widget.gridSize - gap) / 2;

    return Column(
      children: [
        SizedBox(
          height: itemHeight,
          width: widget.gridSize,
          child: _buildSharedPhotoThumbnail(files[0]),
        ),
        const SizedBox(height: gap),
        SizedBox(
          height: itemHeight,
          width: widget.gridSize,
          child: _buildSharedPhotoThumbnail(files[1]),
        ),
      ],
    );
  }

  Widget _buildThreePhotos(List<EnteFile> files) {
    const gap = 2.0;
    final itemWidth = (widget.gridSize - gap) / 2;
    final itemHeight = (widget.gridSize - gap) / 2;

    return Column(
      children: [
        // Top row: 2 photos
        Row(
          children: [
            SizedBox(
              height: itemHeight,
              width: itemWidth,
              child: _buildSharedPhotoThumbnail(files[0]),
            ),
            const SizedBox(width: gap),
            SizedBox(
              height: itemHeight,
              width: itemWidth,
              child: _buildSharedPhotoThumbnail(files[1]),
            ),
          ],
        ),
        const SizedBox(height: gap),
        // Bottom row: 1 photo spanning full width
        SizedBox(
          height: itemHeight,
          width: widget.gridSize,
          child: _buildSharedPhotoThumbnail(files[2]),
        ),
      ],
    );
  }

  Widget _buildFourPlusPhotos(List<EnteFile> files, int extraCount) {
    const gap = 2.0;
    final itemWidth = (widget.gridSize - gap) / 2;
    final itemHeight = (widget.gridSize - gap) / 2;

    return Column(
      children: [
        // Top row
        Row(
          children: [
            SizedBox(
              height: itemHeight,
              width: itemWidth,
              child: _buildSharedPhotoThumbnail(files[0]),
            ),
            const SizedBox(width: gap),
            SizedBox(
              height: itemHeight,
              width: itemWidth,
              child: _buildSharedPhotoThumbnail(files[1]),
            ),
          ],
        ),
        const SizedBox(height: gap),
        // Bottom row
        Row(
          children: [
            SizedBox(
              height: itemHeight,
              width: itemWidth,
              child: _buildSharedPhotoThumbnail(files[2]),
            ),
            const SizedBox(width: gap),
            // Fourth photo with optional +N overlay
            SizedBox(
              height: itemHeight,
              width: itemWidth,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildSharedPhotoThumbnail(files[3]),
                  if (extraCount > 0) _buildExtraCountOverlay(extraCount),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSharedPhotoThumbnail(EnteFile file) {
    final thumbnail = Hero(
      tag: widget.heroTagPrefix + file.tag,
      child: ThumbnailWidget(
        file,
        fit: BoxFit.cover,
        rawThumbnail: false,
        shouldShowFavoriteIcon: false,
        shouldShowSyncStatus: false,
        shouldShowLivePhotoOverlay: true,
        thumbnailSize: thumbnailLargeSize,
        useRequestedThumbnailSizeForLocalCache: true,
      ),
    );
    final fileID = file.uploadedFileID;
    if (widget.onPhotoTap == null || fileID == null) {
      return thumbnail;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onPhotoTap!(fileID),
      child: thumbnail,
    );
  }

  Widget _buildExtraCountOverlay(int extraCount) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '+$extraCount',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final tappableBadge = widget.onExtraCountTap == null
        ? badge
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onExtraCountTap,
            child: badge,
          );

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(padding: const EdgeInsets.all(6), child: tappableBadge),
    );
  }
}
