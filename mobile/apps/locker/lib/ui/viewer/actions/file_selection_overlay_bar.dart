import 'package:ente_components/ente_components.dart';
import "package:ente_events/event_bus.dart";
import "package:ente_icons/ente_icons.dart";
import "package:ente_ui/components/buttons/button_widget.dart";
import "package:ente_ui/utils/dialog_util.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/events/collections_updated_event.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/models/selected_files.dart";
import "package:locker/services/collections/collections_service.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/services/collections/models/collection_view_type.dart";
import "package:locker/services/configuration.dart";
import "package:locker/services/db/locker_db.dart";
import "package:locker/services/favorites_service.dart";
import "package:locker/services/files/offline/offline_files_service.dart";
import "package:locker/services/files/sync/models/file.dart";
import "package:locker/services/trash/trash_service.dart";
import "package:locker/ui/components/add_to_collection_sheet.dart";
import "package:locker/ui/components/delete_confirmation_sheet.dart";
import "package:locker/ui/components/selection_action_button_widget.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";
import "package:locker/utils/collection_list_util.dart";
import "package:locker/utils/error_sheet.dart";
import "package:locker/utils/file_actions.dart";
import "package:locker/utils/file_util.dart";
import "package:logging/logging.dart";

class FileSelectionOverlayBar extends StatefulWidget {
  final SelectedFiles selectedFiles;
  final List<EnteFile> files;
  final CollectionViewType? collectionViewType;
  final ScrollController? scrollController;
  final bool isTrashMode;

  const FileSelectionOverlayBar({
    required this.selectedFiles,
    required this.files,
    this.collectionViewType,
    this.scrollController,
    this.isTrashMode = false,
    super.key,
  });

  @override
  State<FileSelectionOverlayBar> createState() =>
      _FileSelectionOverlayBarState();
}

class _FileSelectionOverlayBarState extends State<FileSelectionOverlayBar> {
  static final Logger _logger = Logger("FileSelectionOverlayBar");

  static const double _scrollThreshold = 10.0;

  bool _isExpanded = true;
  double _lastScrollPosition = 0;
  int _previousSelectionCount = 0;

  bool get hasSelection => widget.selectedFiles.files.isNotEmpty;

  List<EnteFile> _getOwnedFiles(List<EnteFile> files) {
    final currentUserID = Configuration.instance.getUserID();
    final ownedFiles = files
        .where((file) => file.ownerID == currentUserID)
        .toList();

    final sharedCount = files.length - ownedFiles.length;
    if (sharedCount > 0 && mounted) {
      showToast(
        context,
        context.l10n.actionNotSupportedForSharedFiles(sharedCount),
      );
    }

    return ownedFiles;
  }

  @override
  void initState() {
    super.initState();
    widget.selectedFiles.addListener(_onSelectionChanged);
    widget.scrollController?.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.selectedFiles.removeListener(_onSelectionChanged);
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;

    final currentCount = widget.selectedFiles.files.length;
    final isFirstSelection = _previousSelectionCount == 0 && currentCount > 0;

    if (isFirstSelection) {
      setState(() => _isExpanded = true);
    } else {
      setState(() {});
    }

    _previousSelectionCount = currentCount;
  }

  void _onScroll() {
    final controller = widget.scrollController;
    if (!mounted || controller == null || !hasSelection) return;

    final position = controller.position;
    final current = position.pixels;

    if (current < 0 || current > position.maxScrollExtent) return;

    final delta = current - _lastScrollPosition;
    if (delta.abs() < _scrollThreshold) return;

    _lastScrollPosition = current;

    final shouldCollapse = delta > 0 && _isExpanded;
    final shouldExpand = delta < 0 && !_isExpanded;

    if (shouldCollapse || shouldExpand) {
      setState(() => _isExpanded = !_isExpanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final colors = context.componentColors;

    return IgnorePointer(
      ignoring: !hasSelection,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          offset: hasSelection ? Offset.zero : const Offset(0, 1),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: hasSelection ? 1.0 : 0.0,
            curve: Curves.easeInOut,
            child: hasSelection
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (details) {
                      if (details.primaryDelta != null) {
                        if (details.primaryDelta! < -5 && !_isExpanded) {
                          setState(() => _isExpanded = true);
                        } else if (details.primaryDelta! > 5 && _isExpanded) {
                          setState(() => _isExpanded = false);
                        }
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.backgroundBase,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                        border: Border(
                          top: BorderSide(color: colors.strokeDark),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                ListenableBuilder(
                                  listenable: widget.selectedFiles,
                                  builder: (context, child) {
                                    final selectedSet =
                                        widget.selectedFiles.files;
                                    final isAllSelected =
                                        widget.files.isNotEmpty &&
                                        widget.files.every(
                                          (file) => selectedSet.contains(file),
                                        );
                                    final buttonText = isAllSelected
                                        ? context.l10n.deselectAll
                                        : context.l10n.selectAll;
                                    final iconData = isAllSelected
                                        ? Icons.remove_circle_outline
                                        : Icons.check_circle_outline_outlined;

                                    return InkWell(
                                      onTap: () {
                                        if (isAllSelected) {
                                          widget.selectedFiles.clearAll();
                                        } else {
                                          widget.selectedFiles.selectAll(
                                            widget.files.toSet(),
                                          );
                                        }
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: colors.fillLight,
                                          borderRadius: BorderRadius.circular(
                                            50,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12.0,
                                          vertical: 10.0,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              buttonText,
                                              style: TextStyles.body,
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                              iconData,
                                              color: colors.textBase,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const Spacer(),
                                ListenableBuilder(
                                  listenable: widget.selectedFiles,
                                  builder: (context, child) {
                                    final count = widget.selectedFiles.count;
                                    final countText = context.l10n
                                        .selectedCount(count);

                                    return InkWell(
                                      onTap: () {
                                        widget.selectedFiles.clearAll();
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: colors.fillLight,
                                          borderRadius: BorderRadius.circular(
                                            50,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12.0,
                                          vertical: 10.0,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              countText,
                                              style: TextStyles.body,
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                              Icons.close,
                                              color: colors.textBase,
                                              semanticLabel: "close",
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildActionButtons(),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return ListenableBuilder(
      listenable: widget.selectedFiles,
      builder: (context, child) {
        final selectedFiles = widget.selectedFiles.files;
        if (selectedFiles.isEmpty) {
          return const SizedBox.shrink();
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPrimaryActionRow(selectedFiles),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                crossFadeState: _isExpanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Column(
                  children: [
                    const SizedBox(height: 12),
                    _buildSecondaryActionRow(selectedFiles),
                  ],
                ),
                secondChild: const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrimaryActionRow(Set<EnteFile> selectedFiles) {
    final files = selectedFiles.toList();
    final colors = context.componentColors;

    if (widget.isTrashMode) {
      return _buildTrashActionRow(files, colors);
    }

    final isSingleSelection = selectedFiles.length == 1;
    final file = isSingleSelection ? files.first : null;
    final viewType = widget.collectionViewType;

    final isImportant =
        isSingleSelection &&
        file != null &&
        FavoritesService.instance.isFavoriteCache(file);

    final showImportant = viewType?.showMarkImportantOption ?? true;
    final showDelete = viewType?.showDeleteOption ?? true;

    final eligibleOfflineFiles = OfflineFilesService.instance.getEligibleFiles(
      files,
    );
    final showOffline = viewType?.showOfflineOption ?? true;
    final actions = <Widget>[];

    if (showOffline && eligibleOfflineFiles.isNotEmpty) {
      final shouldRemoveOffline =
          isSingleSelection &&
          eligibleOfflineFiles.length == 1 &&
          LockerDB.instance.isFileMarkedOffline(eligibleOfflineFiles.first);

      actions.add(
        SelectionActionButton(
          hugeIcon: SvgPicture.asset(
            shouldRemoveOffline
                ? "assets/svg/cloud_only.svg"
                : "assets/svg/keep_offline.svg",
            width: 22,
            height: 22,
            colorFilter: ColorFilter.mode(colors.textBase, BlendMode.srcIn),
          ),
          label: shouldRemoveOffline
              ? context.l10n.cloudOnly
              : context.l10n.keepOffline,
          onTap: () => _toggleOfflineAvailability(
            context,
            files,
            shouldRemoveOffline: shouldRemoveOffline,
          ),
        ),
      );
    }

    if (showImportant) {
      actions.add(
        SelectionActionButton(
          icon: isImportant ? EnteIcons.favoriteFilled : null,
          hugeIcon: isImportant
              ? null
              : HugeIcon(
                  icon: HugeIcons.strokeRoundedStar,
                  color: colors.textBase,
                ),
          label: isImportant
              ? context.l10n.unimportant
              : context.l10n.important,
          onTap: () => isSingleSelection
              ? _markImportant(context, file!)
              : _markMultipleImportant(context, files),
        ),
      );
    }

    if (showDelete) {
      actions.add(
        SelectionActionButton(
          hugeIcon: HugeIcon(
            icon: HugeIcons.strokeRoundedDelete02,
            color: colors.warning,
          ),
          label: context.l10n.delete,
          onTap: () => isSingleSelection
              ? _deleteFile(context, file!)
              : _deleteMultipleFiles(context, files),
          isDestructive: true,
        ),
      );
    }

    return Row(children: _buildActionRow(actions));
  }

  Widget _buildTrashActionRow(List<EnteFile> files, ColorTokens colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: _buildActionRow([
          SelectionActionButton(
            hugeIcon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
            label: context.l10n.restore,
            onTap: () => _restoreFiles(context, files),
          ),
          SelectionActionButton(
            hugeIcon: HugeIcon(
              icon: HugeIcons.strokeRoundedDelete02,
              color: colors.warning,
            ),
            label: context.l10n.delete,
            onTap: () => _deleteFromTrash(context, files),
            isDestructive: true,
          ),
        ]),
      ),
    );
  }

  Widget _buildSecondaryActionRow(Set<EnteFile> selectedFiles) {
    final actions = _getSecondaryActionsForSelection(selectedFiles);

    if (actions.isEmpty || widget.isTrashMode) {
      return const SizedBox.shrink();
    }

    final colors = context.componentColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(children: _buildActionRow(actions, spacing: 0)),
    );
  }

  List<Widget> _buildActionRow(List<Widget> actions, {double spacing = 12}) {
    final children = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      children.add(Expanded(child: actions[i]));
      if (i != actions.length - 1 && spacing > 0) {
        children.add(SizedBox(width: spacing));
      }
    }
    return children;
  }

  List<Widget> _getSecondaryActionsForSelection(Set<EnteFile> selectedFiles) {
    final isSingleSelection = selectedFiles.length == 1;
    final file = isSingleSelection ? selectedFiles.first : null;
    final files = selectedFiles.toList();
    final viewType = widget.collectionViewType;
    final actions = <Widget>[];

    final showEdit = viewType?.showEditOption ?? true;
    final showShare = viewType?.showShareOption ?? true;
    final showAddTo = viewType?.showAddToCollectionOption ?? true;

    if (isSingleSelection && showEdit) {
      actions.add(
        SelectionActionButton(
          hugeIcon: const HugeIcon(icon: HugeIcons.strokeRoundedPencilEdit02),
          label: context.l10n.edit,
          onTap: () => _editFile(context, file!),
        ),
      );
    }

    if (isSingleSelection && showShare) {
      actions.add(
        SelectionActionButton(
          hugeIcon: const HugeIcon(icon: HugeIcons.strokeRoundedNavigation06),
          label: context.l10n.share,
          onTap: () => _shareFileLink(context, file!),
        ),
      );
    }

    if (showAddTo) {
      actions.add(
        SelectionActionButton(
          hugeIcon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowRight03),
          label: context.l10n.addTo,
          onTap: () => _showAddToDialog(context, files),
        ),
      );
    }

    actions.add(
      SelectionActionButton(
        hugeIcon: const HugeIcon(icon: HugeIcons.strokeRoundedDownload01),
        label: context.l10n.download,
        onTap: () => isSingleSelection
            ? _downloadFile(context, file!)
            : _downloadMultipleFiles(context, files),
      ),
    );

    return actions;
  }

  Future<void> _toggleOfflineAvailability(
    BuildContext context,
    List<EnteFile> files, {
    required bool shouldRemoveOffline,
  }) async {
    late final bool success;
    if (shouldRemoveOffline) {
      success = await OfflineFilesService.instance.unmarkFilesOffline(
        context,
        files,
      );
    } else {
      success = await OfflineFilesService.instance.markFilesOffline(
        context,
        files,
      );
    }

    if (success && mounted) {
      widget.selectedFiles.clearAll();
    }
  }

  Future<void> _downloadFile(BuildContext context, EnteFile file) async {
    try {
      final success = await FileUtil.downloadFile(context, file);
      if (success && mounted) {
        widget.selectedFiles.clearAll();
      }
    } catch (e, stackTrace) {
      _logger.severe("Failed to download file: $e", e, stackTrace);
      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
  }

  Future<void> _downloadMultipleFiles(
    BuildContext context,
    List<EnteFile> files,
  ) async {
    if (files.isEmpty) {
      return;
    }

    try {
      final success = await FileUtil.downloadFiles(context, files);
      if (success && mounted) {
        widget.selectedFiles.clearAll();
      }
    } catch (e, stackTrace) {
      _logger.severe("Failed to download files: $e", e, stackTrace);
      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
  }

  Future<void> _shareFileLink(BuildContext context, EnteFile file) async {
    final currentUserID = Configuration.instance.getUserID();
    if (file.ownerID != currentUserID) {
      showToast(context, context.l10n.shareNotSupportedForSharedFiles);
      return;
    }
    await FileActions.shareFileLink(context, file);
  }

  Future<void> _editFile(BuildContext context, EnteFile file) async {
    final currentUserID = Configuration.instance.getUserID();
    if (file.ownerID != currentUserID) {
      showToast(context, context.l10n.editNotSupportedForSharedFiles);
      return;
    }
    await FileActions.editFile(context, file);
    if (mounted) {
      widget.selectedFiles.clearAll();
    }
  }

  Future<void> _showAddToDialog(
    BuildContext context,
    List<EnteFile> files,
  ) async {
    final ownedFiles = _getOwnedFiles(files);
    if (ownedFiles.isEmpty) {
      return;
    }

    _logger.info(
      'Opening add-to dialog for ${ownedFiles.length} file(s); fetching collections.',
    );

    final allCollections = await CollectionService.instance.getCollectionsForUI(
      includeUncategorized: true,
    );
    final dedupedCollections = uniqueCollectionsById(allCollections);
    _logger.info(
      'Presenting ${dedupedCollections.length} unique collection option(s) '
      'to add files to.',
    );

    if (!context.mounted) return;
    final result = await showAddToCollectionSheet(
      context,
      collections: dedupedCollections,
    );

    if (result == null) return;

    _logger.info(
      'Add-to dialog submitted with '
      '${result.selectedCollections.length} selected collection(s).',
    );
    final dialog = context.mounted
        ? createProgressDialog(
            context,
            context.l10n.pleaseWait,
            isDismissible: false,
          )
        : null;

    await dialog?.show();

    try {
      final addFutures = <Future<void>>[];

      for (final file in ownedFiles) {
        _logger.fine(
          'Processing file ${file.uploadedFileID} for add-to operation',
        );
        List<Collection> currentCollections;
        try {
          currentCollections = await CollectionService.instance
              .getCollectionsForFile(file);
        } catch (_) {
          _logger.warning(
            'Failed to fetch existing collections for file ${file.uploadedFileID}',
          );
          currentCollections = <Collection>[];
        }

        final currentCollectionIds = currentCollections
            .map((collection) => collection.id)
            .toSet();

        final collectionsToAdd = result.selectedCollections.where(
          (collection) => !currentCollectionIds.contains(collection.id),
        );

        for (final collection in collectionsToAdd) {
          _logger.fine(
            'Adding file ${file.uploadedFileID} to collection ${collection.id}.',
          );
          addFutures.add(
            CollectionService.instance.addToCollection(
              collection,
              file,
              runSync: false,
            ),
          );
        }
      }

      if (addFutures.isEmpty) {
        await dialog?.hide();
        if (mounted) {
          widget.selectedFiles.clearAll();
        }
        if (context.mounted) {
          showToast(context, context.l10n.noChangesWereMade);
        }
        return;
      }

      await Future.wait(addFutures);
      await CollectionService.instance.sync();
      _logger.info(
        'Completed add-to operation for ${ownedFiles.length} file(s).',
      );

      await dialog?.hide();

      if (mounted) {
        widget.selectedFiles.clearAll();
      }
      if (context.mounted) {
        showToast(context, context.l10n.fileUpdatedSuccessfully);
      }
    } catch (e) {
      await dialog?.hide();
      _logger.severe('Failed add-to operation: $e');

      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
  }

  Future<void> _deleteFile(BuildContext context, EnteFile file) async {
    final currentUserID = Configuration.instance.getUserID();
    if (file.ownerID != currentUserID) {
      showToast(context, context.l10n.deleteNotSupportedForSharedFiles);
      return;
    }
    await FileActions.deleteFile(
      context,
      file,
      onSuccess: () {
        if (mounted) {
          widget.selectedFiles.clearAll();
        }
        Bus.instance.fire(CollectionsUpdatedEvent('file_deleted'));
      },
    );
  }

  Future<void> _deleteMultipleFiles(
    BuildContext context,
    List<EnteFile> files,
  ) async {
    final ownedFiles = _getOwnedFiles(files);
    if (ownedFiles.isEmpty) {
      return;
    }

    final confirmation = await showDeleteConfirmationSheet(
      context,
      title: context.l10n.areYouSure,
      body: context.l10n.deleteMultipleFilesDialogBody(ownedFiles.length),
      deleteButtonLabel: context.l10n.yesDeleteFiles(ownedFiles.length),
      illustration: LockerBottomSheetIllustration.fileDelete,
    );

    if (confirmation?.buttonResult.action != ButtonAction.first) {
      return;
    }

    final dialog = context.mounted
        ? createProgressDialog(
            context,
            context.l10n.deletingFile,
            isDismissible: false,
          )
        : null;

    try {
      await dialog?.show();

      for (final file in ownedFiles) {
        final collections = await CollectionService.instance
            .getCollectionsForFile(file);

        if (collections.isNotEmpty) {
          await CollectionService.instance.trashFile(file, collections.first);
        }
      }

      await dialog?.hide();

      if (mounted) {
        widget.selectedFiles.clearAll();
      }
      if (context.mounted) {
        showToast(context, context.l10n.fileDeletedSuccessfully);
      }
    } catch (e, stackTrace) {
      await dialog?.hide();

      _logger.severe(
        'Failed to delete files via selection bar: $e',
        e,
        stackTrace,
      );
      if (!context.mounted) {
        return;
      }
      await showLockerErrorSheet(context, e);
    }
  }

  Future<void> _markImportant(BuildContext context, EnteFile file) async {
    final currentUserID = Configuration.instance.getUserID();
    if (file.ownerID != currentUserID) {
      showToast(context, context.l10n.importantNotSupportedForSharedFiles);
      return;
    }
    await FileActions.markImportant(
      context,
      file,
      onSuccess: () {
        if (mounted) {
          widget.selectedFiles.clearAll();
        }
        Bus.instance.fire(CollectionsUpdatedEvent('file_important_toggled'));
      },
    );
  }

  Future<void> _markMultipleImportant(
    BuildContext context,
    List<EnteFile> files,
  ) async {
    final ownedFiles = _getOwnedFiles(files);
    if (ownedFiles.isEmpty) {
      return;
    }

    await FileActions.markMultipleImportant(
      context,
      ownedFiles,
      onSuccess: () {
        if (mounted) {
          widget.selectedFiles.clearAll();
        }
        Bus.instance.fire(CollectionsUpdatedEvent('files_marked_important'));
      },
    );
  }

  Future<void> _restoreFiles(BuildContext context, List<EnteFile> files) async {
    _logger.info('Opening restore dialog for ${files.length} file(s)');

    final allCollections = await CollectionService.instance.getCollectionsForUI(
      includeUncategorized: true,
    );
    final dedupedCollections = uniqueCollectionsById(allCollections);

    if (!context.mounted) return;
    final result = await showAddToCollectionSheet(
      context,
      collections: dedupedCollections,
    );

    if (result == null || result.selectedCollections.isEmpty) {
      return;
    }

    final targetCollection = result.selectedCollections.first;

    final dialog = context.mounted
        ? createProgressDialog(
            context,
            context.l10n.restoringFiles,
            isDismissible: false,
          )
        : null;

    await dialog?.show();

    try {
      await TrashService.instance.restore(files, targetCollection);

      await dialog?.hide();

      if (mounted) {
        widget.selectedFiles.clearAll();
      }

      if (context.mounted) {
        showToast(
          context,
          context.l10n.filesRestoredSuccessfully(files.length),
        );
      }
    } catch (e, stackTrace) {
      await dialog?.hide();
      _logger.severe('Failed to restore files: $e', e, stackTrace);

      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
  }

  Future<void> _deleteFromTrash(
    BuildContext context,
    List<EnteFile> files,
  ) async {
    final confirmation = await showDeleteConfirmationSheet(
      context,
      title: context.l10n.permanentlyDelete,
      body: context.l10n.permanentlyDeleteFilesBody(files.length),
      deleteButtonLabel: context.l10n.yesDelete,
      illustration: LockerBottomSheetIllustration.collectionDelete,
    );

    if (confirmation?.buttonResult.action != ButtonAction.first) {
      return;
    }

    final dialog = context.mounted
        ? createProgressDialog(
            context,
            context.l10n.deletingFiles,
            isDismissible: false,
          )
        : null;

    await dialog?.show();

    try {
      await TrashService.instance.deleteFromTrash(files);

      Bus.instance.fire(CollectionsUpdatedEvent('files_deleted_from_trash'));

      await dialog?.hide();

      if (mounted) {
        widget.selectedFiles.clearAll();
      }

      if (context.mounted) {
        showToast(context, context.l10n.filesDeletedPermanently(files.length));
      }
    } catch (e, stackTrace) {
      await dialog?.hide();
      _logger.severe('Failed to delete files from trash: $e', e, stackTrace);

      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
  }
}
