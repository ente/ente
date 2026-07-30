import "dart:async";

import 'package:ente_components/ente_components.dart';
import 'package:ente_events/event_bus.dart';
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import 'package:locker/events/collections_updated_event.dart';
import "package:locker/extensions/collection_extension.dart";
import 'package:locker/l10n/l10n.dart';
import 'package:locker/models/selected_files.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/collections/models/collection.dart';
import "package:locker/services/collections/models/collection_view_type.dart";
import "package:locker/services/configuration.dart";
import 'package:locker/services/files/sync/models/file.dart';
import "package:locker/ui/components/collection_popup_menu_widget.dart";
import "package:locker/ui/components/empty_state_widget.dart";
import 'package:locker/ui/components/item_list_view.dart';
import 'package:locker/ui/components/search_result_view.dart';
import 'package:locker/ui/mixins/search_mixin.dart';
import 'package:locker/ui/pages/home_page.dart';
import 'package:locker/ui/pages/uploader_page.dart';
import "package:locker/ui/sharing/share_collection_bottom_sheet.dart";
import "package:locker/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:locker/utils/error_sheet.dart";
import "package:logging/logging.dart";

class CollectionPage extends UploaderPage {
  final Collection collection;
  final bool isUncategorized;

  const CollectionPage({
    super.key,
    required this.collection,
    this.isUncategorized = false,
  });

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends UploaderPageState<CollectionPage>
    with SearchMixin {
  final _logger = Logger("CollectionPage");
  late StreamSubscription<CollectionsUpdatedEvent>
  _collectionUpdateSubscription;

  late Collection _collection;
  List<EnteFile> _files = [];
  List<EnteFile> _filteredFiles = [];
  late CollectionViewType collectionViewType;
  bool isQuickLink = false;
  bool isFavorite = false;

  final _selectedFiles = SelectedFiles();
  final _scrollController = ScrollController();
  final _keyboardFocusNode = FocusNode();

  @override
  void onFileUploadComplete() {
    _logger.info(
      "File upload completed from CollectionPage (${widget.collection.id}), refreshing collection data",
    );
    CollectionService.instance.getCollections().then((collections) {
      setState(() {
        _initializeData(collections.where((c) => c.id == _collection.id).first);
      });
    });
  }

  @override
  List<Collection> get allCollections => [];

  @override
  List<EnteFile> get allFiles => _files;

  @override
  Collection get selectedCollection => _collection;

  @override
  void onSearchResultsChanged(
    List<Collection> collections,
    List<EnteFile> files,
  ) {
    setState(() {
      _filteredFiles = files;
    });
  }

  @override
  void onSearchStateChanged(bool isActive) {
    if (!isActive) {
      setState(() {
        _filteredFiles = _files;
      });
    }
  }

  @override
  void dispose() {
    _collectionUpdateSubscription.cancel();
    _keyboardFocusNode.dispose();
    _scrollController.dispose();
    _selectedFiles.dispose();
    super.dispose();
  }

  List<EnteFile> get _displayedFiles =>
      isSearchActive ? _filteredFiles : _files;

  bool get _isSelectionEnabled =>
      collectionViewType != CollectionViewType.quickLink;

  @override
  void initState() {
    super.initState();
    _initializeData(widget.collection);
    _collectionUpdateSubscription = Bus.instance.on<CollectionsUpdatedEvent>().listen((
      event,
    ) async {
      _logger.info(
        "CollectionsUpdatedEvent received on CollectionPage (${widget.collection.id}): ${event.source}",
      );
      if (!mounted) return;

      try {
        final collections = await CollectionService.instance.getCollections();

        final matchingCollection = collections.where(
          (c) => c.id == widget.collection.id,
        );

        if (matchingCollection.isNotEmpty) {
          await _initializeData(matchingCollection.first);
        } else {
          _logger.warning(
            'Collection ${widget.collection.id} no longer exists, navigating back',
          );
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      } catch (e) {
        _logger.severe('Error updating collection', e);
      }
    });

    collectionViewType = getCollectionViewType(
      _collection,
      Configuration.instance.getUserID()!,
    );
    isFavorite = collectionViewType == CollectionViewType.favorite;
    isQuickLink = collectionViewType == CollectionViewType.quickLink;
  }

  Future<void> _initializeData(Collection collection) async {
    _collection = collection;
    _files = await CollectionService.instance.getFilesInCollection(_collection);
    _filteredFiles = _files;
    setState(() {});
  }

  Future<void> _shareCollection() async {
    try {
      if ((collectionViewType != CollectionViewType.ownedCollection &&
          collectionViewType != CollectionViewType.sharedCollectionViewer &&
          collectionViewType !=
              CollectionViewType.sharedCollectionCollaborator &&
          collectionViewType != CollectionViewType.hiddenOwnedCollection &&
          collectionViewType != CollectionViewType.favorite &&
          !isQuickLink)) {
        throw Exception("Cannot share collection of type $collectionViewType");
      }

      await showShareCollectionSheet(context, collection: _collection);
      if (mounted) {
        setState(() {});
      }
    } catch (e, s) {
      _logger.severe(e, s);
      if (!mounted) return;
      await showLockerErrorSheet(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      onKeyEvent: handleKeyEvent,
      child: Scaffold(
        backgroundColor: colors.backgroundBase,
        body: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            AppBarComponent(
              title: _collection.displayName ?? context.l10n.untitled,
              subtitle: context.l10n.items(_displayedFiles.length),
              actions: _buildActions(),
              controller: _scrollController,
              slivers: _buildSlivers(context),
            ),
            FileSelectionOverlayBar(
              files: _displayedFiles,
              selectedFiles: _selectedFiles,
              collectionViewType: collectionViewType,
              scrollController: _scrollController,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActions() {
    if (widget.isUncategorized || isFavorite) {
      return const [];
    }

    final actions = <Widget>[];

    final canShare =
        collectionViewType == CollectionViewType.ownedCollection ||
        collectionViewType == CollectionViewType.hiddenOwnedCollection ||
        collectionViewType == CollectionViewType.sharedCollectionViewer ||
        collectionViewType == CollectionViewType.sharedCollectionCollaborator ||
        isQuickLink;
    if (canShare) {
      actions.add(
        IconButtonComponent(
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedShare08),
          variant: IconButtonComponentVariant.primary,
          shouldSurfaceExecutionStates: false,
          onTap: _shareCollection,
        ),
      );
    }

    final canManageCollection = canShare;
    if (canManageCollection) {
      actions.add(CollectionPopupMenuWidget(collection: _collection));
    }

    return actions;
  }

  List<Widget> _buildSlivers(BuildContext context) {
    if (isSearchActive) {
      return [
        SliverToBoxAdapter(
          child: SearchResultView(
            collections: const [],
            files: _filteredFiles,
            searchQuery: searchQuery,
            isHomePage: false,
            onSearchEverywhere: _searchEverywhere,
          ),
        ),
      ];
    }

    if (_displayedFiles.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: EmptyStateWidget(
                assetPath: 'assets/empty_state.png',
                title: context.l10n.collectionEmptyStateTitle,
                subtitle: context.l10n.collectionEmptyStateSubtitle,
                showBorder: false,
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        sliver: SliverToBoxAdapter(
          child: ItemListView(
            key: ValueKey(_displayedFiles.length),
            files: _displayedFiles,
            selectedFiles: _selectedFiles,
            selectionEnabled: _isSelectionEnabled,
          ),
        ),
      ),
    ];
  }

  void _searchEverywhere() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => HomePage(initialSearchQuery: searchQuery),
      ),
      (route) => false,
    );
  }
}
