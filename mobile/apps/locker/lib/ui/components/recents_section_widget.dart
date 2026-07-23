import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import "package:hugeicons/hugeicons.dart";
import "package:locker/extensions/collection_extension.dart";
import 'package:locker/l10n/l10n.dart';
import "package:locker/models/selected_files.dart";
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/files/sync/models/file.dart';
import "package:locker/ui/components/empty_state_widget.dart";
import 'package:locker/ui/components/item_list_view.dart';
import 'package:locker/ui/pages/all_collections_page.dart';

class RecentsSectionWidget extends StatefulWidget {
  final List<Collection> collections;
  final List<EnteFile> recentFiles;
  final SelectedFiles? selectedFiles;
  final ValueNotifier<List<EnteFile>>? displayedFilesNotifier;

  const RecentsSectionWidget({
    super.key,
    required this.collections,
    required this.recentFiles,
    this.selectedFiles,
    this.displayedFilesNotifier,
  });

  @override
  State<RecentsSectionWidget> createState() => _RecentsSectionWidgetState();
}

class _RecentsSectionWidgetState extends State<RecentsSectionWidget> {
  final Set<Collection> _selectedCollections = {};
  final List<Collection> _selectionOrder = [];
  List<EnteFile> _filteredFiles = [];
  List<Collection> _availableCollections = [];
  late List<Collection> _originalCollectionOrder;
  int _filtersComputationId = 0;
  final Map<int, List<Collection>> _fileCollectionsCache = {};
  final Map<int, Future<List<Collection>>> _fileCollectionsRequests = {};

  @override
  void initState() {
    super.initState();
    _originalCollectionOrder = List.from(widget.collections);
    _availableCollections = List.from(widget.collections);
    // Update notifier with initial displayed files after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateDisplayedFilesNotifier();
    });
  }

  void _updateDisplayedFilesNotifier() {
    if (!mounted) return;
    widget.displayedFilesNotifier?.value = _displayedFiles;
  }

  @override
  void didUpdateWidget(RecentsSectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recentFiles != widget.recentFiles ||
        oldWidget.collections != widget.collections) {
      _handleCollectionUpdates();
      _fileCollectionsCache.clear();
      _fileCollectionsRequests.clear();
      setState(() {
        _originalCollectionOrder = List.from(widget.collections);
        if (!_hasActiveFilters) {
          _availableCollections = List.from(widget.collections);
        }
      });
      _updateFilteredFiles();
      // Update notifier when source files change and no filters are active
      if (!_hasActiveFilters) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateDisplayedFilesNotifier();
        });
      }
    }
  }

  bool get _hasActiveFilters => _selectedCollections.isNotEmpty;

  List<EnteFile> get _displayedFiles =>
      _hasActiveFilters ? _filteredFiles : widget.recentFiles;

  @override
  Widget build(BuildContext context) {
    final filterChipsRow = _buildFilterChipsRow();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filterChipsRow != null) ...[
          filterChipsRow,
          const SizedBox(height: 16),
        ],
        _buildRecentsTable(context),
      ],
    );
  }

  Widget? _buildFilterChipsRow() {
    final orderedFilters = _getOrderedCollections();

    if (orderedFilters.isEmpty) {
      return null;
    }

    return _FilterChipsRow(
      chips: _buildFilterChipModels(context, orderedFilters),
      onFilterIconTapped: () => _showFilterBottomSheet(context),
    );
  }

  void _showFilterBottomSheet(BuildContext context) {
    final navigator = Navigator.of(context);

    showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            final orderedFilters = _getOrderedCollections();

            return _FilterBottomSheet(
              chips: _buildFilterChipModels(
                context,
                orderedFilters,
                afterTap: () => setBottomSheetState(() {}),
              ),
              onSeeAllCollections: () {
                navigator.pop();
                navigator.push(
                  MaterialPageRoute(
                    builder: (context) => const AllCollectionsPage(),
                  ),
                );
              },
              onClearAllFilters: () async {
                await _clearAllFilters();
                setBottomSheetState(() {});
              },
            );
          },
        );
      },
    );
  }

  List<_FilterChipViewModel> _buildFilterChipModels(
    BuildContext context,
    List<Collection> collections, {
    VoidCallback? afterTap,
  }) {
    return collections
        .map(
          (collection) => _FilterChipViewModel(
            key: 'c_${collection.id}',
            label: _collectionLabel(context, collection),
            isSelected: _selectedCollections.contains(collection),
            onTap: () async {
              await _onCollectionSelected(collection);
              afterTap?.call();
            },
          ),
        )
        .toList();
  }

  Widget _buildRecentsTable(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeInOutExpo,
      switchOutCurve: Curves.easeInOutExpo,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[...previousChildren, ?currentChild],
        );
      },
      child: _displayedFiles.isEmpty
          ? EmptyStateWidget(
              key: const ValueKey('empty_state'),
              assetPath: "assets/empty_state.png",
              subtitle: context.l10n.noItemsMatchSelectedFilters,
            )
          : ItemListView(
              key: const ValueKey('items_list'),
              files: _displayedFiles,
              selectedFiles: widget.selectedFiles,
            ),
    );
  }

  Future<void> _onCollectionSelected(Collection collection) async {
    await HapticFeedback.lightImpact();

    setState(() {
      if (_selectedCollections.contains(collection)) {
        _selectedCollections.remove(collection);
        _selectionOrder.remove(collection);
      } else {
        _selectedCollections.add(collection);
        _selectionOrder.add(collection);
      }
    });

    await _updateFilteredFiles();
  }

  Future<void> _clearAllFilters() async {
    await HapticFeedback.lightImpact();

    setState(() {
      _selectedCollections.clear();
      _selectionOrder.clear();
    });

    await _updateFilteredFiles();
  }

  void _handleCollectionUpdates() {
    final updatedCollectionIds = widget.collections.map((c) => c.id).toSet();
    final removedCollections = _selectedCollections
        .where((collection) => !updatedCollectionIds.contains(collection.id))
        .toList();

    if (removedCollections.isEmpty) {
      return;
    }

    setState(() {
      for (final collection in removedCollections) {
        _selectedCollections.remove(collection);
        _selectionOrder.remove(collection);
      }
    });
  }

  Future<void> _updateFilteredFiles() async {
    final int computationId = ++_filtersComputationId;
    final hasCollectionFilters = _selectedCollections.isNotEmpty;

    if (!hasCollectionFilters) {
      if (!mounted || computationId != _filtersComputationId) {
        return;
      }

      setState(() {
        _filteredFiles = [];
        _availableCollections = List.from(widget.collections);
      });

      // Update notifier when filters are cleared
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateDisplayedFilesNotifier();
      });
      return;
    }

    final fileCollections = await _ensureCollectionsForFiles(
      widget.recentFiles,
      refresh: true,
    );

    if (!mounted || computationId != _filtersComputationId) {
      return;
    }

    final filteredFiles = <EnteFile>[];
    final filteredFileCollections = <int, List<Collection>>{};
    final selectedCollectionIds = _selectedCollections
        .map((collection) => collection.id)
        .toSet();

    for (final file in widget.recentFiles) {
      final fileId = file.uploadedFileID;
      final collectionsForFile = fileId != null
          ? (fileCollections[fileId] ?? const <Collection>[])
          : const <Collection>[];

      final collectionIdsForFile = collectionsForFile
          .map((collection) => collection.id)
          .toSet();

      if (!selectedCollectionIds.every(collectionIdsForFile.contains)) {
        continue;
      }

      filteredFiles.add(file);
      if (fileId != null) {
        filteredFileCollections[fileId] = collectionsForFile;
      }
    }

    final availableCollections = _computeAvailableCollections(
      filteredFiles: filteredFiles,
      fileCollections: filteredFileCollections,
    );

    if (!mounted || computationId != _filtersComputationId) {
      return;
    }

    setState(() {
      _filteredFiles = filteredFiles;
      _availableCollections = availableCollections;
    });

    // Update notifier with the new displayed files
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateDisplayedFilesNotifier();
    });
  }

  Future<Map<int, List<Collection>>> _ensureCollectionsForFiles(
    List<EnteFile> files, {
    bool refresh = false,
  }) async {
    final List<Future<void>> pending = [];

    for (final file in files) {
      final fileId = file.uploadedFileID;
      if (fileId == null) {
        continue;
      }

      if (refresh) {
        _fileCollectionsCache.remove(fileId);
        // Drop any in-flight request so a fresh fetch is triggered.
        final _ = _fileCollectionsRequests.remove(fileId);
      }

      if (_fileCollectionsCache.containsKey(fileId)) {
        continue;
      }

      final existingRequest = _fileCollectionsRequests[fileId];
      if (existingRequest != null) {
        pending.add(
          existingRequest
              .then((collections) {
                _fileCollectionsCache[fileId] = collections;
              })
              .whenComplete(() {
                _fileCollectionsRequests.remove(fileId);
              }),
        );
        continue;
      }

      final request = CollectionService.instance.getCollectionsForFile(file);
      _fileCollectionsRequests[fileId] = request;
      pending.add(
        request
            .then((collections) {
              _fileCollectionsCache[fileId] = collections;
            })
            .whenComplete(() {
              _fileCollectionsRequests.remove(fileId);
            }),
      );
    }

    if (pending.isNotEmpty) {
      try {
        await Future.wait(pending);
      } catch (_) {
        // Ignore individual failures; missing entries default to empty lists.
      }
    }

    final result = <int, List<Collection>>{};
    for (final file in files) {
      final fileId = file.uploadedFileID;
      if (fileId == null) {
        continue;
      }
      result[fileId] = _fileCollectionsCache[fileId] ?? const [];
    }

    return result;
  }

  List<Collection> _computeAvailableCollections({
    required List<EnteFile> filteredFiles,
    required Map<int, List<Collection>> fileCollections,
  }) {
    final availableIds = <int>{};

    for (final file in filteredFiles) {
      final fileId = file.uploadedFileID;
      if (fileId == null) {
        continue;
      }
      for (final collection in fileCollections[fileId] ?? const []) {
        availableIds.add(collection.id);
      }
    }

    if (availableIds.isEmpty && _selectedCollections.isNotEmpty) {
      for (final collection in _selectedCollections) {
        availableIds.add(collection.id);
      }
    }

    final ordered = <Collection>[];
    final seen = <int>{};

    for (final collection in widget.collections) {
      if (availableIds.contains(collection.id) && seen.add(collection.id)) {
        ordered.add(collection);
      }
    }

    for (final collection in _selectedCollections) {
      if (seen.add(collection.id)) {
        ordered.add(collection);
      }
    }

    return ordered;
  }

  List<Collection> _getOrderedCollections() {
    final orderedCollections = <Collection>[];

    for (final collection in _selectionOrder) {
      if (_availableCollections.contains(collection)) {
        orderedCollections.add(collection);
      }
    }

    for (final collection in _originalCollectionOrder) {
      if (_availableCollections.contains(collection) &&
          !_selectedCollections.contains(collection)) {
        orderedCollections.add(collection);
      }
    }

    return orderedCollections;
  }

  String _collectionLabel(BuildContext context, Collection collection) {
    final name = collection.displayName?.trim();
    if (name == null || name.isEmpty) {
      return context.l10n.untitled;
    }
    return name;
  }
}

class _FilterChipViewModel {
  const _FilterChipViewModel({
    required this.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String key;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({
    required this.chips,
    required this.onFilterIconTapped,
  });

  final List<_FilterChipViewModel> chips;
  final VoidCallback onFilterIconTapped;

  @override
  Widget build(BuildContext context) {
    final listKey = chips.map((chip) => chip.key).join('-');

    return Row(
      children: [
        IconButtonComponent(
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedFilterHorizontal),
          variant: IconButtonComponentVariant.primary,
          shouldSurfaceExecutionStates: false,
          tooltip: context.l10n.filters,
          onTap: onFilterIconTapped,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: SizedBox(
                    key: ValueKey(listKey),
                    width: constraints.maxWidth,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(right: 24),
                      child: Row(
                        children: chips.map((chip) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            child: TagChipComponent(
                              label: chip.label,
                              state: chip.isSelected
                                  ? TagChipComponentState.selected
                                  : TagChipComponentState.unselected,
                              onTap: chip.onTap,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterBottomSheet extends StatelessWidget {
  const _FilterBottomSheet({
    required this.chips,
    required this.onSeeAllCollections,
    required this.onClearAllFilters,
  });

  final List<_FilterChipViewModel> chips;
  final VoidCallback onSeeAllCollections;
  final VoidCallback onClearAllFilters;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              _ActionPillButton(
                label: context.l10n.seeAllCollections,
                onTap: onSeeAllCollections,
                colors: colors,
              ),
              const Spacer(),
              _ActionPillButton(
                label: context.l10n.clearAllFilters,
                onTap: onClearAllFilters,
                colors: colors,
              ),
            ],
          ),
        ),
        BottomSheetComponent(
          title: context.l10n.filters,
          content: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: chips.map((chip) {
                    return TagChipComponent(
                      label: chip.label,
                      state: chip.isSelected
                          ? TagChipComponentState.selected
                          : TagChipComponentState.unselected,
                      onTap: chip.onTap,
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionPillButton extends StatelessWidget {
  const _ActionPillButton({
    required this.label,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final VoidCallback onTap;
  final ColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.fillLight,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: colors.strokeFaint, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Text(label, style: TextStyles.body),
      ),
    );
  }
}
