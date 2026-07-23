import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:locker/l10n/l10n.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/ui/components/collection_selection_widget.dart';
import 'package:locker/utils/collection_list_util.dart';

class FileEditSheetResult {
  final String title;
  final String caption;
  final List<Collection> selectedCollections;

  FileEditSheetResult({
    required this.title,
    required this.caption,
    required this.selectedCollections,
  });
}

class FileEditSheet extends StatefulWidget {
  final EnteFile file;
  final List<Collection> collections;

  const FileEditSheet({
    super.key,
    required this.file,
    required this.collections,
  });

  @override
  State<FileEditSheet> createState() => _FileEditSheetState();
}

class _FileEditSheetState extends State<FileEditSheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();
  final Set<int> _selectedCollectionIds = <int>{};
  List<Collection> _availableCollections = [];
  bool _hasLoadedCollectionSelection = false;

  bool get _canSave =>
      _hasLoadedCollectionSelection &&
      _selectedCollectionIds.isNotEmpty &&
      _titleController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _availableCollections = _filterCollections(widget.collections);
    _titleController.text = widget.file.displayName;
    _captionController.text = widget.file.caption ?? '';
    _initializeSelections();
  }

  Future<void> _initializeSelections() async {
    try {
      final existingCollections = await CollectionService.instance
          .getCollectionsForFile(widget.file);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedCollectionIds
          ..clear()
          ..addAll(existingCollections.map((collection) => collection.id));
        _hasLoadedCollectionSelection = true;
      });
    } catch (_) {
      // Ignore failures; selections will remain empty.
      if (mounted) {
        setState(() {
          _hasLoadedCollectionSelection = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  void _toggleCollection(int collectionId) {
    setState(() {
      if (_selectedCollectionIds.contains(collectionId)) {
        _selectedCollectionIds.remove(collectionId);
      } else {
        _selectedCollectionIds.add(collectionId);
      }
    });
  }

  void _onCollectionsUpdated(List<Collection> updatedCollections) {
    setState(() {
      _availableCollections = _filterCollections(updatedCollections);
      _selectedCollectionIds.removeWhere(
        (id) => !_availableCollections.any((c) => c.id == id),
      );
    });
  }

  List<Collection> _filterCollections(List<Collection> source) {
    return uniqueCollectionsById(source);
  }

  void _onSave() {
    final selectedCollections = _availableCollections
        .where((c) => _selectedCollectionIds.contains(c.id))
        .toList();
    final result = FileEditSheetResult(
      title: _titleController.text.trim(),
      caption: _captionController.text.trim(),
      selectedCollections: selectedCollections,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheetComponent(
      title: context.l10n.editItem,
      isKeyboardAware: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextInputComponent(
            isRequired: true,
            controller: _titleController,
            label: context.l10n.title,
            hintText: context.l10n.enterNewTitle,
            maxLength: 200,
          ),
          const SizedBox(height: 24),
          CollectionSelectionWidget(
            collections: _availableCollections,
            selectedCollectionIds: _selectedCollectionIds,
            onToggleCollection: _toggleCollection,
            onCollectionsUpdated: _onCollectionsUpdated,
            title: context.l10n.collections,
          ),
        ],
      ),
      actions: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _titleController,
          builder: (context, _, _) => ButtonComponent(
            label: context.l10n.save,
            onTap: _canSave ? _onSave : null,
          ),
        ),
      ],
    );
  }
}

Future<FileEditSheetResult?> showFileEditSheet(
  BuildContext context, {
  required EnteFile file,
  required List<Collection> collections,
}) {
  return showBottomSheetComponent<FileEditSheetResult>(
    context: context,
    builder: (_) => FileEditSheet(file: file, collections: collections),
  );
}
