import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/ui/components/collection_selection_widget.dart";
import "package:locker/utils/collection_list_util.dart";

class AddToCollectionSheetResult {
  final List<Collection> selectedCollections;

  AddToCollectionSheetResult({required this.selectedCollections});
}

class AddToCollectionSheet extends StatefulWidget {
  final List<Collection> collections;
  final bool allowMultiple;

  const AddToCollectionSheet({
    super.key,
    required this.collections,
    this.allowMultiple = true,
  });

  @override
  State<AddToCollectionSheet> createState() => _AddToCollectionSheetState();
}

class _AddToCollectionSheetState extends State<AddToCollectionSheet> {
  final Set<int> _selectedCollectionIds = <int>{};
  List<Collection> _availableCollections = [];

  bool get _canSave => _selectedCollectionIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _availableCollections = uniqueCollectionsById(widget.collections);
  }

  void _toggleCollection(int collectionId) {
    setState(() {
      if (_selectedCollectionIds.contains(collectionId)) {
        _selectedCollectionIds.remove(collectionId);
      } else {
        if (!widget.allowMultiple) _selectedCollectionIds.clear();
        _selectedCollectionIds.add(collectionId);
      }
    });
  }

  void _onCollectionsUpdated(List<Collection> updatedCollections) {
    setState(() {
      _availableCollections = uniqueCollectionsById(updatedCollections);
    });
  }

  void _onSave() {
    final selectedCollections = _availableCollections
        .where((c) => _selectedCollectionIds.contains(c.id))
        .toList();
    Navigator.of(
      context,
    ).pop(AddToCollectionSheetResult(selectedCollections: selectedCollections));
  }

  @override
  Widget build(BuildContext context) {
    final maxCollectionListHeight = MediaQuery.sizeOf(context).height * 0.6;

    return BottomSheetComponent(
      title: context.strings.addToCollection,
      content: CollectionSelectionWidget(
        collections: _availableCollections,
        selectedCollectionIds: _selectedCollectionIds,
        onToggleCollection: _toggleCollection,
        onCollectionsUpdated: _onCollectionsUpdated,
        maxHeight: maxCollectionListHeight,
        title: context.strings.collections,
      ),
      actions: [
        ButtonComponent(
          label: context.strings.save,
          onTap: _canSave ? _onSave : null,
        ),
      ],
    );
  }
}

Future<AddToCollectionSheetResult?> showAddToCollectionSheet(
  BuildContext context, {
  required List<Collection> collections,
  bool allowMultiple = true,
}) {
  return showBottomSheetComponent<AddToCollectionSheetResult>(
    context: context,
    builder: (_) => AddToCollectionSheet(
      collections: collections,
      allowMultiple: allowMultiple,
    ),
  );
}
