import "package:ente_components/ente_components.dart";
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:ente_ui/utils/toast_util.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:locker/extensions/collection_extension.dart";
import "package:locker/l10n/l10n.dart";
import 'package:locker/models/file_type.dart';
import 'package:locker/models/selected_collections.dart';
import 'package:locker/models/selected_files.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/services/info_file_service.dart';
import "package:locker/ui/components/collection_list_widget.dart";
import "package:locker/ui/components/empty_state_widget.dart";
import "package:locker/ui/components/file_list_widget.dart";
import 'package:locker/ui/pages/collection_page.dart';
import 'package:locker/utils/collection_sort_util.dart';

class ItemListView extends StatefulWidget {
  static const double _selectionOverlayPadding = 200.0;

  final List<EnteFile> files;
  final List<Collection> collections;
  final Widget? emptyStateWidget;
  final SelectedCollections? selectedCollections;
  final SelectedFiles? selectedFiles;
  final ScrollPhysics? physics;
  final ScrollController? scrollController;
  final bool selectionEnabled;

  const ItemListView({
    super.key,
    this.files = const [],
    this.collections = const [],
    this.emptyStateWidget,
    this.selectedCollections,
    this.selectedFiles,
    this.physics = const NeverScrollableScrollPhysics(),
    this.scrollController,
    this.selectionEnabled = true,
  });

  @override
  State<ItemListView> createState() => _ItemListViewState();
}

class _ItemListViewState extends State<ItemListView> {
  List<_ListItem> _sortedItems = [];

  @override
  void initState() {
    super.initState();
    _updateItems();
  }

  @override
  void didUpdateWidget(ItemListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.files != oldWidget.files ||
        widget.collections != oldWidget.collections) {
      _updateItems();
    }
  }

  void _updateItems() {
    final sortedCollections = CollectionSortUtil.getSortedCollections(
      widget.collections,
    );

    _sortedItems = [
      ...sortedCollections.map((c) => _CollectionListItem(c)),
      ...widget.files.map((f) => _FileListItem(f)),
    ];
  }

  Future<void> _navigateToCollectionPage(Collection collection) async {
    await routeToPage(context, CollectionPage(collection: collection));
  }

  void _toggleCollectionSelection(Collection collection) {
    HapticFeedback.lightImpact();
    widget.selectedCollections!.toggleSelection(collection);
  }

  void _toggleFileSelection(EnteFile file) {
    if (!widget.selectionEnabled) {
      showToast(context, "Multi-select for shared files coming soon");
      return;
    }
    HapticFeedback.lightImpact();
    widget.selectedFiles!.toggleSelection(file);
  }

  @override
  Widget build(BuildContext context) {
    if (_sortedItems.isEmpty && widget.emptyStateWidget != null) {
      return widget.emptyStateWidget!;
    }

    if (_sortedItems.isEmpty) {
      return _buildDefaultEmptyState(context);
    }

    final hasFileSelection =
        widget.selectedFiles != null && widget.selectionEnabled;
    final hasCollectionSelection = widget.selectedCollections != null;
    final bottomPadding = (hasFileSelection || hasCollectionSelection)
        ? ItemListView._selectionOverlayPadding
        : 0.0;

    return _buildListView(bottomPadding: bottomPadding);
  }

  Widget _buildListView({double bottomPadding = 0}) {
    return ListView.separated(
      controller: widget.scrollController,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      shrinkWrap: true,
      physics: widget.physics,
      padding: EdgeInsets.only(bottom: bottomPadding),
      itemCount: _sortedItems.length,
      itemBuilder: (context, index) => _buildItem(index),
    );
  }

  Widget _buildItem(int index) {
    final item = _sortedItems[index];

    if (item.isCollection) {
      return _buildCollectionItem(item.collection!);
    } else {
      return _buildFileItem(item.file!);
    }
  }

  Widget _buildCollectionItem(Collection collection) {
    final hasSelection = widget.selectedCollections != null;

    if (hasSelection) {
      return ListenableBuilder(
        listenable: widget.selectedCollections!,
        builder: (context, child) {
          final isAnySelected = widget.selectedCollections!.hasSelections;
          return _createCollectionWidget(
            collection: collection,
            onTap: (c) => isAnySelected
                ? _toggleCollectionSelection(c)
                : _navigateToCollectionPage(c),
            onLongPress: (c) => isAnySelected
                ? _navigateToCollectionPage(c)
                : _toggleCollectionSelection(c),
          );
        },
      );
    }

    return _createCollectionWidget(collection: collection);
  }

  Widget _buildFileItem(EnteFile file) {
    final hasSelection = widget.selectedFiles != null;

    if (hasSelection) {
      return ListenableBuilder(
        listenable: widget.selectedFiles!,
        builder: (context, child) {
          final isAnySelected = widget.selectedFiles!.hasSelections;
          return _createFileWidget(
            file: file,
            onTap: isAnySelected ? (f) => _toggleFileSelection(f) : null,
            onLongPress: isAnySelected ? null : (f) => _toggleFileSelection(f),
          );
        },
      );
    }

    return _createFileWidget(file: file);
  }

  Widget _createCollectionWidget({
    required Collection collection,
    Function(Collection)? onTap,
    Function(Collection)? onLongPress,
  }) {
    return CollectionListWidget(
      collection: collection,
      selectedCollections: widget.selectedCollections,
      onTapCallback: onTap,
      onLongPressCallback: onLongPress,
    );
  }

  Widget _createFileWidget({
    required EnteFile file,
    Function(EnteFile)? onTap,
    Function(EnteFile)? onLongPress,
  }) {
    return FileListWidget(
      file: file,
      selectedFiles: widget.selectedFiles,
      onTapCallback: onTap,
      onLongPressCallback: onLongPress,
    );
  }

  Widget _buildDefaultEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_off,
              size: 64,
              color: context.componentColors.textLight,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.noFilesFound,
              style: TextStyles.body.copyWith(
                color: context.componentColors.textLight,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

abstract class _ListItem {
  String get name;
  DateTime get modificationTime;
  bool get isCollection;

  Collection? get collection => null;
  EnteFile? get file => null;
}

class _CollectionListItem extends _ListItem {
  final Collection _collection;

  _CollectionListItem(this._collection);

  @override
  String get name {
    return _collection.displayName ?? 'Unnamed Collection';
  }

  @override
  DateTime get modificationTime {
    return DateTime.fromMicrosecondsSinceEpoch(_collection.updationTime);
  }

  @override
  bool get isCollection => true;

  @override
  Collection get collection => _collection;
}

class _FileListItem extends _ListItem {
  final EnteFile _file;

  _FileListItem(this._file);

  @override
  String get name {
    // For info files, try to extract the title from the info data
    if (_file.fileType == FileType.info) {
      return InfoFileService.instance.getFileTitleFromFile(_file) ??
          _file.displayName;
    }
    return _file.displayName;
  }

  @override
  DateTime get modificationTime {
    if (_file.updationTime != null) {
      return DateTime.fromMicrosecondsSinceEpoch(_file.updationTime!);
    }
    if (_file.modificationTime != null) {
      return DateTime.fromMillisecondsSinceEpoch(_file.modificationTime!);
    }
    if (_file.creationTime != null) {
      return DateTime.fromMillisecondsSinceEpoch(_file.creationTime!);
    }
    return DateTime.now();
  }

  @override
  bool get isCollection => false;

  @override
  EnteFile get file => _file;
}

class FileListViewHelpers {
  static Widget createSearchEmptyState({
    required BuildContext context,
    required String searchQuery,
    String? message,
  }) {
    return Center(
      child: EmptyStateWidget(
        assetPath: 'assets/empty_state.png',
        title: context.l10n.searchEmptyTitle,
        subtitle: context.l10n.searchEmptyDescription,
        showBorder: false,
      ),
    );
  }

  static Widget createSearchEverywhereFooter({
    required BuildContext context,
    required String searchQuery,
    required VoidCallback onTap,
  }) {
    final colors = context.componentColors;
    return Container(
      margin: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.search, color: colors.primary, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.searchEverywhereTitle(searchQuery),
                        style: TextStyles.large.copyWith(color: colors.primary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.searchEverywhereSubtitle,
                        style: TextStyles.body.copyWith(
                          color: colors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: colors.textLight,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
