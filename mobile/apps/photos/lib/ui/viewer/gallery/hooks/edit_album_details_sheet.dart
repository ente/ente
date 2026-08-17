import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/db/files_db.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/metadata/collection_magic.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/gallery/hooks/pick_cover_photo.dart";

class AlbumDetailsUpdate {
  const AlbumDetailsUpdate({
    required this.name,
    required this.description,
    this.coverID,
  });

  final String name;
  final String description;

  // Null means unchanged; zero restores the default cover.
  final int? coverID;
}

class AlbumCoverSelection {
  const AlbumCoverSelection({required this.id, required this.file});

  final int id;
  final EnteFile? file;
}

Future<void> showEditAlbumDetailsSheet({
  required BuildContext context,
  required Collection collection,
  required Future<void> Function(AlbumDetailsUpdate update) onSave,
}) async {
  final initialCover = CollectionsService.instance.getCover(collection);

  await showBottomSheetComponent<void>(
    context: context,
    builder: (sheetContext) => EditAlbumDetailsSheet(
      initialName: collection.displayName,
      initialDescription: collection.displayDescription ?? "",
      initialCover: initialCover,
      onSelectCover: (pendingCoverID) async {
        final hasEffectiveCustomCover = pendingCoverID == null
            ? collection.hasCover
            : pendingCoverID != 0;
        final coverID = await showPickCoverPhotoSheet(
          sheetContext,
          collection,
          hasEffectiveCustomCover: hasEffectiveCustomCover,
        );
        if (coverID == null) {
          return null;
        }

        final file = coverID == 0
            ? await FilesDB.instance.getCollectionFileFirstOrLast(
                collection.id,
                collection.pubMagicMetadata.asc ?? false,
              )
            : await FilesDB.instance.getUploadedFile(coverID, collection.id);
        return AlbumCoverSelection(id: coverID, file: file);
      },
      onSave: onSave,
    ),
  );
}

class EditAlbumDetailsSheet extends StatefulWidget {
  const EditAlbumDetailsSheet({
    super.key,
    required this.initialName,
    required this.initialDescription,
    required this.initialCover,
    required this.onSelectCover,
    required this.onSave,
  });

  final String initialName;
  final String initialDescription;
  final Future<EnteFile?> initialCover;
  final Future<AlbumCoverSelection?> Function(int? pendingCoverID)
  onSelectCover;
  final Future<void> Function(AlbumDetailsUpdate update) onSave;

  @override
  State<EditAlbumDetailsSheet> createState() => _EditAlbumDetailsSheetState();
}

class _EditAlbumDetailsSheetState extends State<EditAlbumDetailsSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final FocusNode _nameFocusNode;
  late final FocusNode _descriptionFocusNode;
  late Future<EnteFile?> _cover;
  int? _pendingCoverID;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _nameFocusNode = FocusNode();
    _descriptionFocusNode = FocusNode();
    _cover = widget.initialCover;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _nameFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  bool get _hasChanges =>
      _nameController.text.trim() != widget.initialName.trim() ||
      _descriptionController.text.trim() != widget.initialDescription.trim() ||
      _pendingCoverID != null;

  bool get _isSaveDisabled =>
      _nameController.text.trim().isEmpty || !_hasChanges;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _onClose();
        }
      },
      child: BottomSheetComponent(
        title: strings.editDetails,
        closeTooltip: strings.close,
        onClose: _onClose,
        contentSpacing: Spacing.xxl,
        actionsTopSpacing: Spacing.xxl,
        isKeyboardAware: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _AlbumCoverEditor(
                  cover: _cover,
                  onTap: _selectCover,
                  tooltip: strings.setCover,
                ),
                const SizedBox(width: Spacing.lg),
                Expanded(
                  child: TextInputComponent(
                    key: const ValueKey("album_name_input"),
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    label: strings.albumName,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            TextInputComponent(
              key: const ValueKey("album_description_input"),
              controller: _descriptionController,
              focusNode: _descriptionFocusNode,
              label: strings.description,
              hintText: strings.albumDescriptionHint,
              maxLength: maxAlbumDescriptionLength,
              minLines: 5,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        actions: [
          ButtonComponent(
            key: const ValueKey("save_album_details"),
            label: strings.saveChanges,
            isDisabled: _isSaveDisabled,
            dismissModalOnSuccess: true,
            onTap: _save,
          ),
        ],
      ),
    );
  }

  void _onClose() {
    if (!_hasChanges) {
      return;
    }
    FocusScope.of(context).unfocus();
    showBottomSheetComponent<bool>(
      context: context,
      builder: (_) => BottomSheetComponent(
        title: context.strings.unsavedNoteChangesTitle,
        message: context.strings.albumEditsWillNotBeSaved,
        illustration: Image.asset("assets/warning-red.png"),
        actions: [
          ButtonComponent(
            label: context.strings.discardChanges,
            variant: ButtonComponentVariant.critical,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    ).then((shouldDiscard) {
      if (!mounted || shouldDiscard != true) {
        return;
      }
      Navigator.of(context).pop();
    });
  }

  Future<void> _selectCover() async {
    final selection = await widget.onSelectCover(_pendingCoverID);
    if (!mounted || selection == null) {
      return;
    }
    setState(() {
      _pendingCoverID = selection.id;
      _cover = Future.value(selection.file);
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    await widget.onSave(
      AlbumDetailsUpdate(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        coverID: _pendingCoverID,
      ),
    );
  }
}

class _AlbumCoverEditor extends StatelessWidget {
  const _AlbumCoverEditor({
    required this.cover,
    required this.onTap,
    required this.tooltip,
  });

  final Future<EnteFile?> cover;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return SizedBox.square(
      dimension: 108,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.button),
              child: FutureBuilder<EnteFile?>(
                future: cover,
                builder: (context, snapshot) {
                  final file = snapshot.data;
                  if (file == null) {
                    return ColoredBox(
                      color: colors.fillDark,
                      child: Center(
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedImage01,
                          color: colors.textLightest,
                          size: IconSizes.medium,
                        ),
                      ),
                    );
                  }
                  return ThumbnailWidget(
                    file,
                    rawThumbnail: true,
                    shouldShowFavoriteIcon: false,
                    shouldShowSyncStatus: false,
                    shouldShowVideoOverlayIcon: false,
                  );
                },
              ),
            ),
          ),
          Positioned(
            right: -12,
            bottom: -12,
            child: Semantics(
              button: true,
              label: tooltip,
              child: Tooltip(
                message: tooltip,
                child: GestureDetector(
                  key: const ValueKey("edit_album_cover"),
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: SizedBox.square(
                    dimension: 36,
                    child: Center(
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.backgroundBase,
                            width: 1.5,
                          ),
                        ),
                        child: const Center(
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedEdit03,
                            color: Colors.white,
                            size: IconSizes.tiny,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
