import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:ente_events/event_bus.dart';
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import 'package:locker/events/collections_updated_event.dart';
import 'package:locker/l10n/l10n.dart';
import 'package:locker/models/selected_collections.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/ui/components/collection_list_widget.dart';
import "package:locker/ui/components/empty_state_widget.dart";
import 'package:locker/ui/components/item_list_view.dart';
import 'package:locker/ui/pages/collection_page.dart';
import "package:locker/ui/viewer/actions/collection_selection_overlay_bar.dart";
import "package:locker/utils/collection_actions.dart";
import 'package:locker/utils/collection_sort_util.dart';
import 'package:logging/logging.dart';

class AllCollectionsPage extends StatefulWidget {
  const AllCollectionsPage({super.key});

  @override
  State<AllCollectionsPage> createState() => _AllCollectionsPageState();
}

class _AllCollectionsPageState extends State<AllCollectionsPage> {
  List<Collection> _sortedCollections = [];
  Collection? _uncategorizedCollection;
  bool _isLoading = true;
  String? _error;
  bool showUncategorized = false;
  final _logger = Logger("AllCollectionsPage");
  StreamSubscription<CollectionsUpdatedEvent>? _collectionsUpdatedSub;

  final _selectedCollections = SelectedCollections();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCollections(showLoading: true);
    _collectionsUpdatedSub = Bus.instance.on<CollectionsUpdatedEvent>().listen((
      event,
    ) async {
      if (!mounted) return;
      await _loadCollections(showLoading: false);
    });
    showUncategorized = true;
  }

  @override
  void dispose() {
    _collectionsUpdatedSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCollections({bool showLoading = true}) async {
    if (mounted && showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final collections = await CollectionService.instance.getCollections();

      final regularCollections = <Collection>[];
      Collection? uncategorized;
      final userID = Configuration.instance.getUserID()!;

      for (final collection in collections) {
        if (collection.type == CollectionType.uncategorized &&
            collection.isOwner(userID)) {
          uncategorized = collection;
        } else {
          regularCollections.add(collection);
        }
      }

      CollectionSortUtil.sortCollections(regularCollections);

      _sortedCollections = List.from(regularCollections);
      _uncategorizedCollection = uncategorized;

      if (mounted) {
        if (showLoading) {
          setState(() {
            _isLoading = false;
          });
        } else {
          setState(() {});
        }
      }
    } catch (e) {
      _logger.severe("Failed to load collections", e);
      if (mounted && showLoading) {
        setState(() {
          _error = context.l10n.failedToLoadCollections(
            context.l10n.somethingWentWrong,
          );
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final hasCollections =
        !_isLoading && _error == null && _sortedCollections.isNotEmpty;

    final showUncategorizedBar =
        _uncategorizedCollection != null && showUncategorized;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: Stack(
        children: [
          AppBarComponent(
            title: context.l10n.collections,
            subtitle: hasCollections
                ? context.l10n.items(_sortedCollections.length)
                : null,
            actions: hasCollections
                ? [
                    IconButtonComponent(
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
                      variant: IconButtonComponentVariant.primary,
                      shouldSurfaceExecutionStates: false,
                      onTap: () => CollectionActions.createCollection(context),
                    ),
                  ]
                : const [],
            controller: _scrollController,
            slivers: _buildSlivers(context),
          ),
          CollectionSelectionOverlayBar(
            collections: _sortedCollections,
            selectedCollections: _selectedCollections,
          ),
          if (showUncategorizedBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ListenableBuilder(
                listenable: _selectedCollections,
                builder: (context, _) => _selectedCollections.hasSelections
                    ? const SizedBox.shrink()
                    : _buildUncategorizedHook(),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSlivers(BuildContext context) {
    if (_isLoading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                EmptyStateWidget(
                  assetPath: 'assets/empty_state.png',
                  title: context.l10n.somethingWentWrong,
                  subtitle: _error!,
                  showBorder: false,
                ),
                const SizedBox(height: 20),
                ButtonComponent(
                  label: context.l10n.retry,
                  onTap: _loadCollections,
                ),
              ],
            ),
          ),
        ),
      ];
    }

    if (_sortedCollections.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                EmptyStateWidget(
                  assetPath: 'assets/empty_state.png',
                  title: context.l10n.noCollections,
                  subtitle: "",
                  showBorder: false,
                ),
              ],
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
            collections: _sortedCollections,
            selectedCollections: _selectedCollections,
          ),
        ),
      ),
    ];
  }

  Widget _buildUncategorizedHook() {
    if (_uncategorizedCollection == null) return const SizedBox.shrink();

    final colors = context.componentColors;
    return ColoredBox(
      color: colors.backgroundBase,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: CollectionListWidget(
            collection: _uncategorizedCollection!,
            selectedCollections: _selectedCollections,
            onTapCallback: (_) => _openUncategorized(),
          ),
        ),
      ),
    );
  }

  Future<void> _openUncategorized() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CollectionPage(
          collection: _uncategorizedCollection!,
          isUncategorized: true,
        ),
      ),
    );
  }
}
