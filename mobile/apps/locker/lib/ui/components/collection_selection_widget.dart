import 'package:dotted_border/dotted_border.dart';
import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import 'package:locker/extensions/collection_extension.dart';
import 'package:locker/l10n/l10n.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/utils/collection_actions.dart';
import 'package:locker/utils/collection_list_util.dart';

class CollectionSelectionWidget extends StatefulWidget {
  final List<Collection> collections;
  final Set<int> selectedCollectionIds;
  final Function(int) onToggleCollection;
  final Function(List<Collection>)? onCollectionsUpdated;
  final double maxHeight;

  final String title;

  const CollectionSelectionWidget({
    super.key,
    required this.collections,
    required this.selectedCollectionIds,
    required this.onToggleCollection,
    this.onCollectionsUpdated,
    this.maxHeight = 168,
    required this.title,
  });

  @override
  State<CollectionSelectionWidget> createState() =>
      _CollectionSelectionWidgetState();
}

class _CollectionSelectionWidgetState extends State<CollectionSelectionWidget> {
  List<Collection> _availableCollections = [];
  Collection? _uncategorizedCollection;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _updateCollections();
  }

  @override
  void didUpdateWidget(CollectionSelectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collections != widget.collections) {
      _updateCollections();
    }
  }

  void _updateCollections() {
    _availableCollections = uniqueCollectionsById(widget.collections);
    _uncategorizedCollection = findUserUncategorizedCollection(
      _availableCollections,
      Configuration.instance.getUserID()!,
    );
    if (_uncategorizedCollection != null) {
      _availableCollections.removeWhere(
        (collection) => collection.id == _uncategorizedCollection!.id,
      );
    }
  }

  Future<void> _createNewCollection() async {
    final newCollection = await CollectionActions.createCollection(context);

    if (newCollection != null) {
      setState(() {
        _availableCollections.add(newCollection);
      });

      widget.onToggleCollection(newCollection.id);

      widget.onCollectionsUpdated?.call([
        ?_uncategorizedCollection,
        ..._availableCollections,
      ]);
    }
  }

  void _onCollectionTap(int collectionId) {
    widget.onToggleCollection(collectionId);
  }

  @override
  Widget build(BuildContext context) {
    final containsUncategorized = _uncategorizedCollection != null;

    final chips = <Widget>[];

    chips.add(_buildNewCollectionChip());

    if (containsUncategorized) {
      chips.add(
        TagChipComponent(
          label: context.l10n.uncategorized,
          state:
              widget.selectedCollectionIds.contains(
                _uncategorizedCollection?.id ?? -1,
              )
              ? TagChipComponentState.selected
              : TagChipComponentState.unselected,
          onTap: () {
            if (_uncategorizedCollection != null) {
              _onCollectionTap(_uncategorizedCollection!.id);
            }
          },
        ),
      );
    }

    for (final collection in _availableCollections) {
      final collectionName =
          collection.displayName ?? context.l10n.unnamedCollection;
      chips.add(
        TagChipComponent(
          label: collectionName,
          state: widget.selectedCollectionIds.contains(collection.id)
              ? TagChipComponentState.selected
              : TagChipComponentState.unselected,
          onTap: () => _onCollectionTap(collection.id),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title.isNotEmpty) ...[
          Text(widget.title, style: TextStyles.bodyBold),
          const SizedBox(height: 8),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: SizedBox(
              width: double.infinity,
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                radius: const Radius.circular(4),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(right: 12, bottom: 12),
                  child: Wrap(spacing: 8, runSpacing: 12, children: chips),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNewCollectionChip() {
    final colors = context.componentColors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await _createNewCollection();
      },
      child: DottedBorder(
        options: RoundedRectDottedBorderOptions(
          strokeWidth: 1,
          padding: EdgeInsets.zero,
          color: colors.textLighter,
          dashPattern: const [5, 5],
          radius: const Radius.circular(16),
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 18, color: colors.textLight),
              const SizedBox(width: 6),
              Text(
                context.l10n.collectionLabel,
                style: TextStyles.body.copyWith(color: colors.textLight),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Collection> get availableCollections => _availableCollections;
}
