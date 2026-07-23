import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/collection/collection_items.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/collections/collection_action_sheet.dart";
import "package:photos/ui/viewer/file_details_new/file_details_skeleton.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";

class AlbumsItemWidgetNew extends StatefulWidget {
  const AlbumsItemWidgetNew({
    required this.file,
    required this.loadDelay,
    required this.showHiddenCollections,
    super.key,
  });

  final EnteFile file;
  final Duration loadDelay;
  final bool showHiddenCollections;

  @override
  State<AlbumsItemWidgetNew> createState() => _AlbumsItemWidgetNewState();
}

class _AlbumsItemWidgetNewState extends State<AlbumsItemWidgetNew> {
  List<Collection>? _collections;
  late final StreamSubscription<CollectionUpdatedEvent> _collectionUpdates;
  Timer? _loadTimer;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.file.uploadedFileID == null) {
      _collections = const [];
    } else {
      _loadTimer = Timer(
        widget.loadDelay,
        () => unawaited(_refreshCollections()),
      );
    }
    _collectionUpdates = Bus.instance.on<CollectionUpdatedEvent>().listen((_) {
      _loadTimer?.cancel();
      unawaited(_refreshCollections());
    });
  }

  Future<void> _refreshCollections() async {
    final generation = ++_loadGeneration;
    final collections = await _loadCollections();
    if (!mounted || generation != _loadGeneration) return;
    setState(() => _collections = collections);
  }

  Future<List<Collection>> _loadCollections() async {
    final fileID = widget.file.uploadedFileID;
    if (fileID == null) return const [];
    try {
      final ids = await FilesDB.instance.getAllCollectionIDsOfFile(fileID);
      return ids
          .map(CollectionsService.instance.getCollectionByID)
          .whereType<Collection>()
          .where(
            (collection) =>
                widget.showHiddenCollections || !collection.isHidden(),
          )
          .toList(growable: false);
    } catch (error, stackTrace) {
      Logger(
        "AlbumsItemWidgetNew",
      ).info("Failed to load albums for file", error, stackTrace);
      return const [];
    }
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _collectionUpdates.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FileDetailsAnimatedSize(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocalizations.of(context).albums,
            style: TextStyles.h2.copyWith(
              color: context.componentColors.textBase,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          if (_collections == null)
            const FileDetailsChipRowSkeleton()
          else
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: _buildChips(context, _collections!),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildChips(BuildContext context, List<Collection> collections) {
    if (widget.file.uploadedFileID == null) {
      final folder = widget.file.deviceFolder ?? "";
      return folder.isEmpty
          ? const []
          : [FilterChipComponent(label: folder, onChanged: (_) {})];
    }
    return [
      for (final collection in collections)
        FilterChipComponent(
          label: collection.isHidden()
              ? AppLocalizations.of(context).hidden
              : collection.displayName,
          onChanged: (_) {
            if (collection.isHidden()) return;
            Bus.instance.fire(PauseVideoEvent());
            routeToPage(
              context,
              CollectionPage(
                CollectionWithThumbnail(collection, null),
                fileToJumpTo: widget.file,
              ),
            );
          },
        ),
      FilterChipComponent(
        avatarSize: IconSizes.small,
        avatar: HugeIcon(
          icon: HugeIcons.strokeRoundedPlusSign,
          size: IconSizes.small,
          color: context.componentColors.textBase,
        ),
        tooltip: AppLocalizations.of(context).addToAlbum,
        onChanged: (_) {
          final selectedFiles = SelectedFiles()..files.add(widget.file);
          showCollectionActionSheet(
            context,
            selectedFiles: selectedFiles,
            actionType: CollectionActionType.addFiles,
          );
        },
      ),
    ];
  }
}
