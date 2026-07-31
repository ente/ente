import "dart:async";
import 'dart:math';

import 'package:collection/collection.dart';
import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/create_new_album_event.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/selected_files.dart';
import "package:photos/service_locator.dart";
import 'package:photos/services/collections_service.dart';
import "package:photos/ui/actions/collection/collection_file_actions.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import 'package:photos/ui/collections/album/vertical_list.dart';
import 'package:photos/ui/common/loading_widget.dart';
import "package:photos/ui/common/progress_dialog.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/separators_util.dart";
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

enum CollectionActionType {
  addFiles,
  moveFiles,
  restoreFiles,
  unHide,
  shareCollection,
  addToHiddenAlbum,
  moveToHiddenCollection,
  autoAddPeople,
}

extension CollectionActionTypeExtension on CollectionActionType {
  bool get isHiddenAction =>
      this == CollectionActionType.moveToHiddenCollection ||
      this == CollectionActionType.addToHiddenAlbum;
}

String _actionName(
  BuildContext context,
  CollectionActionType type,
  int fileCount,
) {
  String text = "";
  switch (type) {
    case CollectionActionType.addFiles:
      text = AppLocalizations.of(context).addItem(count: fileCount);
      break;
    case CollectionActionType.moveFiles:
      text = AppLocalizations.of(context).moveItem(count: fileCount);
      break;
    case CollectionActionType.restoreFiles:
      text = AppLocalizations.of(context).restoreToAlbum;
      break;
    case CollectionActionType.unHide:
      text = AppLocalizations.of(context).unhideToAlbum;
      break;
    case CollectionActionType.shareCollection:
      text = AppLocalizations.of(context).share;
      break;
    case CollectionActionType.addToHiddenAlbum:
      text = AppLocalizations.of(context).addToHiddenAlbum;
      break;
    case CollectionActionType.moveToHiddenCollection:
      text = AppLocalizations.of(context).moveToHiddenAlbum;
      break;
    case CollectionActionType.autoAddPeople:
      text = AppLocalizations.of(context).autoAddToAlbum;
      break;
  }
  return text;
}

Future<void> showCollectionActionSheet(
  BuildContext context, {
  SelectedFiles? selectedFiles,
  List<SharedMediaFile>? sharedFiles,
  CollectionActionType actionType = CollectionActionType.addFiles,
  bool showOptionToCreateNewAlbum = true,
  List<String>? selectedPeople,
}) {
  final topPadding = MediaQuery.paddingOf(context).top;
  final bottomPadding = MediaQuery.paddingOf(context).bottom;
  final screenHeight = MediaQuery.sizeOf(context).height;
  const sheetHeaderHeight = 76.0;
  final sheetTopGap = screenHeight * 0.20;
  final height = max(
    0.0,
    screenHeight - topPadding - bottomPadding - sheetTopGap - sheetHeaderHeight,
  );
  final filesCount = sharedFiles != null
      ? sharedFiles.length
      : selectedPeople != null
      ? selectedPeople.length
      : selectedFiles?.files.length ?? 0;

  return showBottomSheetComponent<void>(
    context: context,
    builder: (_) => BottomSheetComponent(
      title: _actionName(context, actionType, filesCount),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      content: SizedBox(
        height: height,
        child: CollectionActionSheet(
          selectedFiles: selectedFiles,
          sharedFiles: sharedFiles,
          actionType: actionType,
          showOptionToCreateNewAlbum: showOptionToCreateNewAlbum,
          selectedPeople: selectedPeople,
        ),
      ),
    ),
  );
}

class CollectionActionSheet extends StatefulWidget {
  final SelectedFiles? selectedFiles;
  final List<SharedMediaFile>? sharedFiles;
  final List<String>? selectedPeople;
  final CollectionActionType actionType;
  final bool showOptionToCreateNewAlbum;
  const CollectionActionSheet({
    required this.selectedFiles,
    required this.sharedFiles,
    required this.actionType,
    required this.showOptionToCreateNewAlbum,
    this.selectedPeople,
    super.key,
  });

  @override
  State<CollectionActionSheet> createState() => _CollectionActionSheetState();
}

class _CollectionActionSheetState extends State<CollectionActionSheet> {
  late final bool _showOnlyHiddenCollections;
  late final bool _enableSelection;
  static const int okButtonSize = 80;
  String _searchQuery = "";
  final _selectedCollections = <Collection>[];
  final _recentlyCreatedCollections = <Collection>[];
  final _scrollController = ScrollController();
  late StreamSubscription<CreateNewAlbumEvent> _createNewAlbumSubscription;
  final _logger = Logger("CollectionActionSheet");

  @override
  void initState() {
    super.initState();
    _showOnlyHiddenCollections = widget.actionType.isHiddenAction;
    _enableSelection =
        (widget.actionType == CollectionActionType.autoAddPeople &&
            widget.selectedPeople != null) ||
        ((widget.actionType == CollectionActionType.addFiles ||
                widget.actionType == CollectionActionType.addToHiddenAlbum) &&
            (widget.sharedFiles == null || widget.sharedFiles!.isEmpty));
    _createNewAlbumSubscription = Bus.instance.on<CreateNewAlbumEvent>().listen(
      (event) {
        setState(() {
          _recentlyCreatedCollections.insert(0, event.collection);
          _selectedCollections.add(event.collection);
        });
      },
    );
  }

  @override
  void dispose() {
    _createNewAlbumSubscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isKeyboardUp = bottomInset > 100;
    final double bottomPadding = max(
      0,
      bottomInset - (_enableSelection ? okButtonSize : 0),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: isKeyboardUp ? bottomPadding : 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 428),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Column(
                  children: [
                    TextInputComponent(
                      hintText: AppLocalizations.of(
                        context,
                      ).searchByAlbumNameHint,
                      prefix: HugeIcon(
                        icon: HugeIcons.strokeRoundedSearch01,
                        size: 18,
                        color: context.componentColors.textLight,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.trim();
                        });
                      },
                      isClearable: true,
                      shouldUnfocusOnClearOrSubmit: true,
                    ),
                    _getCollectionItems(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(children: [..._actionButtons()]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actionButtons() {
    final List<Widget> widgets = [];
    if (_enableSelection) {
      widgets.add(
        ButtonComponent(
          key: const ValueKey('add_button'),
          label: AppLocalizations.of(context).add,
          shouldSurfaceExecutionStates: false,
          dismissModalOnSuccess: true,
          isDisabled: _selectedCollections.isEmpty,
          onTap: () async {
            if (widget.selectedPeople != null) {
              final ProgressDialog dialog = createProgressDialog(
                context,
                AppLocalizations.of(context).uploadingFilesToAlbum,
                isDismissible: true,
              );
              await dialog.show();
              for (final collection in _selectedCollections) {
                try {
                  await smartAlbumsService.addPeopleToSmartAlbum(
                    collection.id,
                    widget.selectedPeople!,
                  );
                } catch (error, stackTrace) {
                  _logger.severe(
                    "Error while adding people to smart album",
                    error,
                    stackTrace,
                  );
                }
              }
              unawaited(smartAlbumsService.syncSmartAlbums());
              await dialog.hide();
              return;
            }
            final CollectionActions collectionActions = CollectionActions(
              CollectionsService.instance,
            );
            final result = await collectionActions.addToMultipleCollections(
              context,
              _selectedCollections,
              true,
              selectedFiles: widget.selectedFiles?.files.toList(),
            );
            if (result) {
              if (!mounted) return;
              showShortToast(
                context,
                AppLocalizations.of(
                  context,
                ).addedToAlbums(count: _selectedCollections.length),
              );
              widget.selectedFiles?.clearAll();
            }
          },
        ),
      );
    }
    final widgetsWithSpaceBetween = addSeparators(
      widgets,
      const SizedBox(height: 8),
    );
    return widgetsWithSpaceBetween;
  }

  Flexible _getCollectionItems() {
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: FutureBuilder<List<Collection>>(
          future: _getCollections(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              //Need to show an error on the UI here
              return const SizedBox.shrink();
            } else if (snapshot.hasData) {
              final collections = snapshot.data as List<Collection>;
              _removeIncomingCollections(collections);
              final shouldShowCreateAlbum =
                  widget.showOptionToCreateNewAlbum && _searchQuery.isEmpty;

              // Get recently used collections (only when not searching)
              List<Collection> recentCollections = [];
              if (_searchQuery.isEmpty && !_showOnlyHiddenCollections) {
                recentCollections = CollectionsService.instance
                    .getRecentlyUsedCollections()
                    .where((c) => !c.isQuickLinkCollection())
                    .toList();
                // Remove recent collections from the main list to avoid duplicates
                final recentIds = recentCollections.map((c) => c.id).toSet();
                collections.removeWhere((c) => recentIds.contains(c.id));
              }

              // Get shared collections for move action
              List<Collection> sharedCollections = [];
              if (widget.actionType == CollectionActionType.moveFiles) {
                sharedCollections = _getSharedCollections();
                // Filter shared collections by search query
                if (_searchQuery.isNotEmpty) {
                  sharedCollections = sharedCollections
                      .where(
                        (c) => c.displayName.toLowerCase().contains(
                          _searchQuery.toLowerCase(),
                        ),
                      )
                      .toList();
                }
              }

              final searchResults = _searchQuery.isNotEmpty
                  ? collections
                        .where(
                          (element) => element.displayName
                              .toLowerCase()
                              .contains(_searchQuery.toLowerCase()),
                        )
                        .toList()
                  : collections;
              return LayoutBuilder(
                builder: (context, constraints) {
                  return OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: constraints.maxWidth + 20,
                    child: SizedBox(
                      width: constraints.maxWidth + 20,
                      child: Scrollbar(
                        controller: _scrollController,
                        radius: const Radius.circular(2),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 20),
                          child: AlbumVerticalListWidget(
                            searchResults,
                            widget.actionType,
                            widget.selectedFiles,
                            widget.sharedFiles,
                            widget.selectedPeople,
                            _searchQuery,
                            shouldShowCreateAlbum,
                            recentCollections: recentCollections,
                            sharedCollections: sharedCollections,
                            enableSelection: _enableSelection,
                            selectedCollections: _selectedCollections,
                            scrollController: _scrollController,
                            onSelectionChanged: () {
                              setState(() {});
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            } else {
              return const EnteLoadingWidget();
            }
          },
        ),
      ),
    );
  }

  List<Collection> _getSharedCollections() {
    final userID = Configuration.instance.getUserID()!;
    // Get collections where user is collaborator/admin (can add files)
    final allCollections = CollectionsService.instance.getCollectionsForUI(
      includeCollab: true,
      includeUncategorized: false,
    );
    // Filter to only non-owner collections (incoming shared albums)
    final sharedCollections = allCollections
        .where(
          (c) =>
              !c.isOwner(userID) &&
              !c.isQuickLinkCollection() &&
              c.type != CollectionType.favorites,
        )
        .toList();
    sharedCollections.sort((first, second) {
      return compareAsciiLowerCaseNatural(
        first.displayName,
        second.displayName,
      );
    });
    return sharedCollections;
  }

  Future<List<Collection>> _getCollections() async {
    if (_showOnlyHiddenCollections) {
      final List<Collection> recentlyCreated = [];
      final List<Collection> hidden = [];

      final hiddenCollections = CollectionsService.instance
          .getHiddenCollections(includeDefaultHidden: false);
      for (final collection in hiddenCollections) {
        if (_recentlyCreatedCollections.contains(collection)) {
          recentlyCreated.add(collection);
        } else {
          hidden.add(collection);
        }
      }
      hidden.sort((first, second) {
        return compareAsciiLowerCaseNatural(
          first.displayName,
          second.displayName,
        );
      });
      return recentlyCreated + hidden;
    } else {
      final List<Collection>
      collections = CollectionsService.instance.getCollectionsForUI(
        // in collections where user is a collaborator, only addTo and remove
        // action can to be performed
        includeCollab: widget.actionType == CollectionActionType.addFiles,
        includeUncategorized: true,
      );
      collections.sort((first, second) {
        return compareAsciiLowerCaseNatural(
          first.displayName,
          second.displayName,
        );
      });
      final List<Collection> pinned = [];
      final List<Collection> unpinned = [];
      final List<Collection> recentlyCreated = [];
      final userID = Configuration.instance.getUserID()!;
      // show uncategorized collection only for restore files action
      Collection? uncategorized;
      for (final collection in collections) {
        if (collection.isQuickLinkCollection() ||
            collection.type == CollectionType.favorites ||
            (collection.type == CollectionType.uncategorized &&
                collection.isOwner(userID))) {
          if (collection.type == CollectionType.uncategorized) {
            uncategorized = collection;
          }
          continue;
        }
        if (_recentlyCreatedCollections.contains(collection)) {
          recentlyCreated.add(collection);
          continue;
        }
        final bool isPinned =
            collection.isPinned || collection.hasShareePinned();
        if (isPinned) {
          pinned.add(collection);
        } else {
          unpinned.add(collection);
        }
      }

      return uncategorized != null
          ? [uncategorized] + recentlyCreated + pinned + unpinned
          : recentlyCreated + pinned + unpinned;
    }
  }

  void _removeIncomingCollections(List<Collection> items) {
    if (widget.actionType == CollectionActionType.shareCollection) {
      final ownerID = Configuration.instance.getUserID();
      items.removeWhere((e) => !e.isOwner(ownerID!));
    }
  }
}
