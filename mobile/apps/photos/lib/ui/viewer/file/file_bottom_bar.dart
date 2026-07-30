import "dart:async";
import "dart:io";

import "package:ente_icons/ente_icons.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/guest_view_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/trash_file.dart";
import "package:photos/models/selected_files.dart";
import 'package:photos/module/metadata/panorama.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/ui/actions/file/file_actions.dart";
import "package:photos/ui/collections/collection_action_sheet.dart";
import "package:photos/ui/viewer/actions/suggest_delete_sheet.dart";
import "package:photos/utils/delete_file_util.dart";
import "package:photos/utils/share_util.dart";

class FileBottomBar extends StatefulWidget {
  final EnteFile file;
  final Function(EnteFile) onFileRemoved;
  final int? userID;
  final ValueNotifier<bool> enableFullScreenNotifier;
  final bool isLocalOnlyContext;

  const FileBottomBar(
    this.file, {
    required this.onFileRemoved,
    required this.enableFullScreenNotifier,
    this.userID,
    this.isLocalOnlyContext = false,
    super.key,
  });

  @override
  FileBottomBarState createState() => FileBottomBarState();
}

class FileBottomBarState extends State<FileBottomBar> {
  final GlobalKey shareButtonKey = GlobalKey();
  bool isGuestView = false;
  late final StreamSubscription<GuestViewEvent> _guestViewEventSubscription;
  int? lastFileGenID;

  @override
  void initState() {
    super.initState();
    _guestViewEventSubscription = Bus.instance.on<GuestViewEvent>().listen((
      event,
    ) {
      setState(() {
        isGuestView = event.isGuestView;
      });
    });
  }

  @override
  void dispose() {
    _guestViewEventSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.file.canEditMetaInfo &&
        widget.file.canBePanorama() &&
        widget.file.isPanorama() == null) {
      if (lastFileGenID != widget.file.generatedID) {
        lastFileGenID = widget.file.generatedID;
        guardedCheckPanorama(widget.file).ignore();
      }
    }

    final sharedCollectionNotifier = InheritedDetailPageState.maybeOf(
      context,
    )?.isInSharedCollectionNotifier;

    if (sharedCollectionNotifier == null) {
      return _getBottomBar();
    }

    return ValueListenableBuilder<bool>(
      valueListenable: sharedCollectionNotifier,
      builder: (context, _, _) => _getBottomBar(),
    );
  }

  Widget _getBottomBar() {
    final isInSharedCollection =
        InheritedDetailPageState.maybeOf(
          context,
        )?.isInSharedCollectionNotifier.value ??
        false;

    final Collection? collection = widget.file.collectionID != null
        ? CollectionsService.instance.getCollectionByID(
            widget.file.collectionID!,
          )
        : null;
    final List<Widget> children = [];
    final bool isOwnedByUser =
        widget.file.ownerID == null || widget.file.ownerID == widget.userID;
    final bool isFileHidden =
        widget.file.isOwner &&
        widget.file.isUploaded &&
        (collection?.isHidden() ?? false);
    if (widget.file is TrashFile) {
      _addTrashOptions(children);
    }

    if (widget.file is! TrashFile) {
      if (isOwnedByUser) {
        children.add(
          Tooltip(
            message: AppLocalizations.of(context).delete,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: IconButton(
                icon: Icon(
                  Platform.isAndroid
                      ? Icons.delete_outline
                      : CupertinoIcons.delete,
                  color: Colors.white,
                ),
                onPressed: () async {
                  await _showSingleFileDeleteSheet(widget.file);
                },
              ),
            ),
          ),
        );
      }

      final bool canShowSuggestDelete =
          collection != null &&
          flagService.internalUser &&
          isInSharedCollection &&
          canSuggestDeleteForFile(file: widget.file, collection: collection);

      if (canShowSuggestDelete) {
        children.add(_buildSuggestDeleteButton(collection));
      }

      children.add(
        Tooltip(
          message: AppLocalizations.of(context).share,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: IconButton(
              key: shareButtonKey,
              icon: Icon(
                Platform.isAndroid
                    ? Icons.share_outlined
                    : CupertinoIcons.share,
                color: Colors.white,
              ),
              onPressed: () {
                share(context, [widget.file], shareButtonKey: shareButtonKey);
              },
            ),
          ),
        ),
      );

      if (widget.file.isUploaded && !isFileHidden) {
        children.add(
          Tooltip(
            message: AppLocalizations.of(context).addToAlbum,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: IconButton(
                icon: const Icon(
                  EnteIcons.addToAlbum,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () {
                  final selectedFiles = SelectedFiles();
                  selectedFiles.files.add(widget.file);
                  showCollectionActionSheet(
                    context,
                    selectedFiles: selectedFiles,
                    actionType: CollectionActionType.addFiles,
                  );
                },
              ),
            ),
          ),
        );
      }
    }
    return ValueListenableBuilder(
      valueListenable: widget.enableFullScreenNotifier,
      builder: (BuildContext context, bool isFullScreen, _) {
        return IgnorePointer(
          ignoring: isFullScreen || isGuestView,
          child: AnimatedOpacity(
            opacity: isFullScreen || isGuestView ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                    stops: const [0, 0.8, 1],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  left: false,
                  right: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSingleFileDeleteSheet(EnteFile file) async {
    await showSingleFileDeleteSheet(
      context,
      file,
      onFileRemoved: widget.onFileRemoved,
      isLocalOnlyContext: widget.isLocalOnlyContext,
    );
  }

  void _addTrashOptions(List<Widget> children) {
    children.add(
      Tooltip(
        message: AppLocalizations.of(context).restore,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: IconButton(
            icon: const Icon(Icons.restore_outlined, color: Colors.white),
            onPressed: () {
              final selectedFiles = SelectedFiles();
              selectedFiles.toggleSelection(widget.file);
              showCollectionActionSheet(
                context,
                selectedFiles: selectedFiles,
                actionType: CollectionActionType.restoreFiles,
              );
            },
          ),
        ),
      ),
    );

    children.add(
      Tooltip(
        message: AppLocalizations.of(context).delete,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: IconButton(
            icon: const Icon(
              Icons.delete_forever_outlined,
              color: Colors.white,
            ),
            onPressed: () async {
              final trashedFile = <TrashFile>[];
              trashedFile.add(widget.file as TrashFile);
              if (await deleteFromTrash(context, trashedFile) == true) {
                if (!mounted) return;
                Navigator.pop(context);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestDeleteButton(Collection collection) {
    return Tooltip(
      message: AppLocalizations.of(context).suggestDeletion,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: IconButton(
          icon: const Icon(Icons.flag_outlined, color: Colors.white),
          onPressed: () => _onSuggestDelete(collection),
        ),
      ),
    );
  }

  Future<void> _onSuggestDelete(Collection collection) async {
    if (widget.file.uploadedFileID == null) {
      return;
    }
    await showSuggestDeleteSheet(
      context: context,
      onConfirm: () async {
        await CollectionsService.instance.suggestDeleteFromCollection(
          collection.id,
          [widget.file],
        );
        widget.onFileRemoved(widget.file);
      },
    );
  }
}
