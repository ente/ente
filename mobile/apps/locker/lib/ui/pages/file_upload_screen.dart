import 'dart:io';

import "package:ente_components/ente_components.dart";
import "package:ente_ui/components/title_bar_title_widget.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import 'package:locker/l10n/l10n.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/ui/components/collection_selection_widget.dart';
import "package:locker/utils/file_icon_utils.dart";
import 'package:path/path.dart' as path;

class FileUploadScreenResult {
  final String note;
  final List<Collection> selectedCollections;

  FileUploadScreenResult({
    required this.note,
    required this.selectedCollections,
  });
}

class FileUploadScreen extends StatefulWidget {
  final List<File> files;
  final List<Collection> collections;
  final Collection? selectedCollection;

  const FileUploadScreen({
    super.key,
    required this.files,
    required this.collections,
    this.selectedCollection,
  });

  @override
  State<FileUploadScreen> createState() => _FileUploadScreenState();
}

class _FileUploadScreenState extends State<FileUploadScreen> {
  List<File> _files = [];
  List<Collection> _availableCollections = [];
  final Set<int> _selectedCollectionIds = {};

  @override
  void initState() {
    super.initState();
    _files = List.from(widget.files);
    _availableCollections = List.from(widget.collections);

    final selectedCollection = widget.selectedCollection;
    if (selectedCollection != null &&
        (selectedCollection.type != CollectionType.uncategorized ||
            !selectedCollection.isOwner(Configuration.instance.getUserID()!))) {
      _selectedCollectionIds.add(selectedCollection.id);
    }
  }

  @override
  void dispose() {
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
      _availableCollections = updatedCollections;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.backgroundBase,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        elevation: 0,
      ),
      backgroundColor: colors.backgroundBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TitleBarTitleWidget(title: context.l10n.uploadFiles),
                      Text(
                        context.l10n.filesSelected(_files.length),
                        style: TextStyles.body.copyWith(
                          color: colors.textLight,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        color: colors.strokeDark,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.close,
                        size: 24,
                        color: colors.textBase,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: ScrollController(),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_files.isNotEmpty) ...[
                        Container(
                          decoration: BoxDecoration(
                            color: colors.fillDark,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: _files.length > 5
                                    ? 360
                                    : _files.length * 72.0,
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                physics: _files.length > 5
                                    ? const BouncingScrollPhysics()
                                    : const NeverScrollableScrollPhysics(),
                                itemCount: _files.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  return _buildFileItem(_files[index], colors);
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      TitleBarTitleWidget(title: context.l10n.collectionLabel),
                      const SizedBox(height: 16),
                      CollectionSelectionWidget(
                        collections: _availableCollections,
                        selectedCollectionIds: _selectedCollectionIds,
                        onToggleCollection: _toggleCollection,
                        onCollectionsUpdated: _onCollectionsUpdated,
                        title: "",
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SafeArea(
                child: ButtonComponent(
                  label: context.l10n.save,
                  onTap: () async {
                    final selectedCollections = _availableCollections
                        .where((c) => _selectedCollectionIds.contains(c.id))
                        .toList();
                    final result = FileUploadScreenResult(
                      note: '',
                      selectedCollections: selectedCollections,
                    );
                    Navigator.of(context).pop(result);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileItem(File file, ColorTokens colors) {
    final fileName = path.basename(file.path);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
      ),
      child: Row(
        children: [
          SizedBox(height: 40, width: 40, child: _buildFileIcon(fileName)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              fileName,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyles.body,
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              setState(() {
                _files.remove(file);
                if (_files.isEmpty) {
                  Navigator.of(context).pop();
                }
              });
            },
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.strokeDark,
              ),
              padding: const EdgeInsets.all(6),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedCancel01,
                color: colors.textBase,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileIcon(String fileName) {
    return FileIconUtils.getFileIcon(
      context,
      fileName,
      backgroundColor: context.componentColors.backgroundBase,
    );
  }
}
