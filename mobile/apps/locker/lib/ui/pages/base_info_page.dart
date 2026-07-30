import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_ui/utils/toast_util.dart';
import "package:ente_utils/email_util.dart";
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:locker/core/errors.dart';
import 'package:locker/events/user_details_refresh_event.dart';
import 'package:locker/l10n/l10n.dart';
import 'package:locker/models/info/info_item.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/favorites_service.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/services/info_file_service.dart';
import 'package:locker/services/trash/models/trash_file.dart';
import 'package:locker/ui/components/collection_selection_widget.dart';
import 'package:locker/ui/pages/home_page.dart';
import "package:locker/utils/bottom_sheet_illustration.dart";
import "package:locker/utils/error_sheet.dart";
import 'package:logging/logging.dart';

enum InfoPageMode { view, edit }

abstract class BaseInfoPage<T extends InfoData> extends StatefulWidget {
  final InfoPageMode mode;
  final EnteFile? existingFile; // The file to edit, or null for new files
  final VoidCallback? onCancelWithoutSaving;

  const BaseInfoPage({
    super.key,
    this.mode = InfoPageMode.edit,
    this.existingFile,
    this.onCancelWithoutSaving,
  });
}

abstract class BaseInfoPageState<T extends InfoData, W extends BaseInfoPage<T>>
    extends State<W> {
  final _logger = Logger('BaseInfoPageState');
  late InfoPageMode _currentMode;

  @protected
  InfoPageMode get currentMode => _currentMode;

  @protected
  bool get isInViewMode => _currentMode == InfoPageMode.view;

  @protected
  bool get isInEditMode => _currentMode == InfoPageMode.edit;

  // Current data state (can be updated after saving)
  T? _currentData;

  // Collection selection state
  List<Collection> _availableCollections = [];
  Set<int> _selectedCollectionIds = {};
  bool _hasLoadedCollectionSelection = false;

  // Getter for current data - prioritizes updated data over existing file data
  T? get currentData {
    if (_currentData != null) {
      return _currentData;
    }

    // Extract data from existing file if available
    if (widget.existingFile != null) {
      final infoItem = InfoFileService.instance.extractInfoFromFile(
        widget.existingFile!,
      );
      return infoItem?.data as T?;
    }

    return null;
  }

  // Override this method in subclasses to refresh UI when data changes
  void refreshUIWithCurrentData() {
    // Default implementation does nothing
    // Subclasses should override this to update their controllers/state
  }

  // Abstract methods that subclasses must implement
  String get pageTitle;
  String get submitButtonText;
  InfoType get infoType;
  T createInfoData();
  List<Widget> buildFormFields();
  List<Widget> buildViewFields();
  bool validateForm();

  bool get showCollectionSelectionTitle => true;
  double get collectionSpacing => 24;
  double get viewModeBottomPadding => 20;

  @protected
  bool get isSaveEnabled =>
      _hasLoadedCollectionSelection &&
      (widget.existingFile == null || _selectedCollectionIds.isNotEmpty) &&
      validateForm();

  @protected
  void onFieldChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _canEditExistingFile {
    final existingFile = widget.existingFile;
    if (existingFile == null) {
      return true;
    }
    if (existingFile is TrashFile) {
      return false;
    }
    final currentUserID = Configuration.instance.getUserID();
    return currentUserID != null && existingFile.ownerID == currentUserID;
  }

  @protected
  Future<bool> onEditModeBackPressed() async {
    return true;
  }

  @protected
  Future<bool> onPopRequested() async {
    return true;
  }

  @protected
  List<Collection> get availableCollections => _availableCollections;

  @protected
  Set<int> get selectedCollectionIds => _selectedCollectionIds;

  @protected
  void toggleCollectionSelection(int collectionId) {
    _onToggleCollection(collectionId);
  }

  @protected
  void updateAvailableCollections(List<Collection> collections) {
    _onCollectionsUpdated(collections);
  }

  @protected
  Widget buildEditModeContent(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      sliver: SliverList.list(
        children: [
          ...buildFormFields(),
          SizedBox(height: collectionSpacing),
          CollectionSelectionWidget(
            collections: _availableCollections,
            selectedCollectionIds: _selectedCollectionIds,
            onToggleCollection: _onToggleCollection,
            onCollectionsUpdated: _onCollectionsUpdated,
            title: showCollectionSelectionTitle ? context.l10n.collections : '',
          ),
        ],
      ),
    );
  }

  @protected
  Widget buildViewModeContent(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, viewModeBottomPadding),
      sliver: SliverList.list(children: buildViewFields()),
    );
  }

  @override
  void initState() {
    super.initState();
    _currentMode = widget.mode;
    _loadCollections();
    loadExistingData();
  }

  void loadExistingData() {
    // Override in subclasses if needed
  }

  Future<void> _loadCollections() async {
    try {
      final isEditingExistingFile = widget.existingFile != null;
      final filteredCollections = await CollectionService.instance
          .getCollectionsForUI(includeUncategorized: isEditingExistingFile);

      Set<int> initialSelection = _selectedCollectionIds;

      if (isEditingExistingFile) {
        final fileCollections = await CollectionService.instance
            .getCollectionsForFile(widget.existingFile!);
        initialSelection = fileCollections.map((c) => c.id).toSet();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _availableCollections = filteredCollections;
        _selectedCollectionIds = initialSelection;
        _hasLoadedCollectionSelection = true;
      });
    } catch (e) {
      // Handle error silently or show a message
    }
  }

  void _onToggleCollection(int collectionId) {
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

  Future<void> _saveRecord() async {
    if (!validateForm()) {
      return;
    }

    try {
      // Create InfoItem using the subclass implementation
      final infoData = createInfoData();
      final infoItem = InfoItem(
        type: infoType,
        data: infoData,
        createdAt: DateTime.now(),
      );

      if (widget.existingFile != null) {
        // Update existing file
        await _updateExistingFile(infoItem);
      } else {
        // Create new file
        await _createNewFile(infoItem);
      }

      if (mounted && widget.existingFile != null) {
        // Switch to view mode with updated data
        setState(() {
          _currentMode = InfoPageMode.view;
        });

        showToast(context, context.l10n.recordSavedSuccessfully);
      }
    } on StorageLimitExceededError {
      if (mounted) {
        showToast(context, context.l10n.uploadStorageLimitErrorBody);
      }
    } on NoActiveSubscriptionError {
      if (mounted) {
        await _showUploadErrorSheet(
          context.l10n.uploadSubscriptionExpiredErrorTitle,
          context.l10n.uploadSubscriptionExpiredErrorBody,
        );
      }
    } on FileLimitReachedError {
      if (mounted) {
        showToast(context, context.l10n.uploadFileCountLimitErrorToast);
      }
    } catch (e) {
      if (mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
  }

  Future<void> _updateExistingFile(InfoItem infoItem) async {
    if (widget.existingFile == null) return;

    // Use InfoFileService to handle the update logic
    final success = await InfoFileService.instance.updateInfoFile(
      existingFile: widget.existingFile!,
      updatedInfoItem: infoItem,
    );

    if (!success) {
      throw Exception('Failed to update file metadata');
    }

    // Handle collection membership changes
    await _updateCollectionMembership();

    if (!mounted) return;

    // Update the local data to reflect the changes in the UI
    // Use the infoItem data directly since it contains the updated values
    setState(() {
      _currentData = infoItem.data as T?;
    });

    // Refresh UI with updated data
    refreshUIWithCurrentData();

    // The info file service already performs a sync, so we don't need to sync again
  }

  Future<void> _updateCollectionMembership() async {
    if (widget.existingFile == null) return;
    if (!_hasLoadedCollectionSelection) return;

    // Get current collections for the file
    final currentCollections = await CollectionService.instance
        .getCollectionsForFile(widget.existingFile!);

    // Fetch all collections to ensure we have the latest state
    final allCollections = await CollectionService.instance.getCollections();

    // Get the favorites/important collection for special handling
    final favoriteCollection = await CollectionService.instance
        .getOrCreateImportantCollection();

    final currentCollectionIds = currentCollections.map((c) => c.id).toSet();

    // Check if favorites status changed
    final wasFavorite = currentCollectionIds.contains(favoriteCollection.id);
    final isFavoriteNow = _selectedCollectionIds.contains(
      favoriteCollection.id,
    );

    if (wasFavorite && !isFavoriteNow) {
      await FavoritesService.instance.removeFromFavorites(widget.existingFile!);
    } else if (!wasFavorite && isFavoriteNow) {
      await FavoritesService.instance.addToFavorites(widget.existingFile!);
    }

    // Only favorites is special-cased; Uncategorized is treated as a normal
    // collection. A file can belong to multiple collections (incl.
    // Uncategorized), so it is only removed from Uncategorized when the user
    // explicitly deselects it.
    final regularCurrentIds = currentCollectionIds
        .where((id) => id != favoriteCollection.id)
        .toSet();
    final regularSelectedIds = _selectedCollectionIds
        .where((id) => id != favoriteCollection.id)
        .toSet();

    final collectionsToAdd = regularSelectedIds.difference(regularCurrentIds);
    final collectionsToRemove = regularCurrentIds.difference(
      regularSelectedIds,
    );

    // If all regular collections are deselected, move to uncategorized
    if (regularSelectedIds.isEmpty && collectionsToRemove.isNotEmpty) {
      for (final collectionId in collectionsToRemove) {
        try {
          final collection = allCollections.firstWhere(
            (c) => c.id == collectionId,
          );
          await CollectionService.instance.moveFilesFromCurrentCollection(
            mounted ? context : null,
            collection,
            [widget.existingFile!],
          );
        } catch (e) {
          _logger.severe(
            'Failed to remove file from collection $collectionId: $e',
          );
        }
      }
    } else {
      // Add to new collections
      for (final collectionId in collectionsToAdd) {
        try {
          final collection = allCollections.firstWhere(
            (c) => c.id == collectionId,
          );
          await CollectionService.instance.addToCollection(
            collection,
            widget.existingFile!,
            runSync: false,
          );
        } catch (e) {
          _logger.severe('Failed to add file to collection $collectionId: $e');
        }
      }

      // Remove from deselected collections
      for (final collectionId in collectionsToRemove) {
        try {
          final collection = allCollections.firstWhere(
            (c) => c.id == collectionId,
          );
          await CollectionService.instance.moveFilesFromCurrentCollection(
            mounted ? context : null,
            collection,
            [widget.existingFile!],
          );
        } catch (e) {
          _logger.severe(
            'Failed to remove file from collection $collectionId: $e',
          );
        }
      }
    }

    await CollectionService.instance.sync();
  }

  Future<void> _createNewFile(InfoItem infoItem) async {
    final selectedCollections = _availableCollections
        .where((c) => _selectedCollectionIds.contains(c.id))
        .toList();

    if (selectedCollections.isEmpty) {
      final uncategorizedCollection = await CollectionService.instance
          .getOrCreateUncategorizedCollection();
      selectedCollections.add(uncategorizedCollection);
    }

    // Upload to the first collection
    final uploadedFile = await InfoFileService.instance.createAndUploadInfoFile(
      infoItem: infoItem,
      collection: selectedCollections.first,
    );

    // Add to additional collections if multiple were selected
    for (int i = 1; i < selectedCollections.length; i++) {
      await CollectionService.instance.addToCollection(
        selectedCollections[i],
        uploadedFile,
        runSync: false,
      );
    }

    // Trigger sync after successful save
    await CollectionService.instance.sync();
    Bus.instance.fire(UserDetailsRefreshEvent());

    if (!mounted) return;

    // Show success message
    final collectionCount = selectedCollections.length;
    final message = collectionCount == 1
        ? context.l10n.recordSavedSuccessfully
        : context.l10n.recordSavedToMultipleCollections(collectionCount);

    // Navigate to home page and clear all previous routes
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const HomePage()),
      (route) => false,
    );

    // Show success message after navigation
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        showToast(context, message);
      }
    });
  }

  Future<void> _showUploadErrorSheet(String title, String message) async {
    await showBottomSheetComponent(
      context: context,
      isDismissible: true,
      enableDrag: true,
      builder: (_) => BottomSheetComponent(
        title: title,
        message: message,
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.l10n.contactSupport,
            onTap: () async {
              await sendEmail(context, to: "support@ente.com", body: message);
            },
          ),
        ],
      ),
    );
  }

  void _toggleMode() {
    setState(() {
      _currentMode = _currentMode == InfoPageMode.view
          ? InfoPageMode.edit
          : InfoPageMode.view;
    });
  }

  void _copyToClipboard(String text, String fieldName) {
    Clipboard.setData(ClipboardData(text: text));
    showToast(context, context.l10n.copiedToClipboard(fieldName));
  }

  Widget buildViewField({
    required String label,
    required String value,
    bool isSecret = false,
    int? maxLines,
    int? minLines,
  }) {
    return _InfoViewField(
      label: label.isEmpty ? null : label,
      value: value,
      isSecret: isSecret,
      maxLines: maxLines,
      minLines: minLines,
      onCopy: () => _copyToClipboard(value, label),
    );
  }

  Future<void> _handleBackNavigation() async {
    if (isInEditMode) {
      final canLeaveEdit = await onEditModeBackPressed();
      if (!canLeaveEdit) {
        return;
      }

      if (currentData != null) {
        _toggleMode();
        return;
      }
    }

    final shouldPop = await onPopRequested();
    if (!shouldPop || !mounted) {
      return;
    }

    _popAndMaybeNotifyCancel();
  }

  void _popAndMaybeNotifyCancel() {
    final shouldNotify =
        widget.existingFile == null && widget.onCancelWithoutSaving != null;
    Navigator.of(context).pop();
    if (shouldNotify) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onCancelWithoutSaving?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isViewMode = _currentMode == InfoPageMode.view;
    final isEditMode = _currentMode == InfoPageMode.edit;
    final colors = context.componentColors;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackNavigation();
        }
      },
      child: Scaffold(
        backgroundColor: colors.backgroundBase,
        body: GestureDetector(
          onTap: Platform.isIOS
              ? () {
                  FocusScope.of(context).unfocus();
                }
              : null,
          behavior: HitTestBehavior.translucent,
          child: Column(
            children: [
              Expanded(
                child: AppBarComponent(
                  title: pageTitle,
                  backgroundColor: colors.backgroundBase,
                  onBack: _handleBackNavigation,
                  actions: [
                    if (isViewMode &&
                        currentData != null &&
                        _canEditExistingFile)
                      IconButtonComponent(
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedEdit03,
                        ),
                        variant: IconButtonComponentVariant.unfilled,
                        shouldSurfaceExecutionStates: false,
                        onTap: _toggleMode,
                        tooltip: context.l10n.edit,
                      ),
                  ],
                  slivers: [
                    isViewMode
                        ? buildViewModeContent(context)
                        : buildEditModeContent(context),
                  ],
                ),
              ),
              if (isEditMode)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: ButtonComponent(
                      label: submitButtonText,
                      onTap: isSaveEnabled ? _saveRecord : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoViewField extends StatefulWidget {
  const _InfoViewField({
    required this.value,
    required this.onCopy,
    this.label,
    this.isSecret = false,
    this.maxLines,
    this.minLines,
  });

  final String? label;
  final String value;
  final VoidCallback onCopy;
  final bool isSecret;
  final int? maxLines;
  final int? minLines;

  @override
  State<_InfoViewField> createState() => _InfoViewFieldState();
}

class _InfoViewFieldState extends State<_InfoViewField> {
  static const _defaultMaxLines = 1;

  final FocusNode _focusNode = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );
  bool _revealed = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final hasValue = widget.value.trim().isNotEmpty;
    final onCopy = hasValue ? widget.onCopy : null;

    if (widget.isSecret) {
      return TextInputComponent(
        label: widget.label,
        focusNode: _focusNode,
        initialValue: _revealed ? widget.value : '••••••••',
        readOnly: true,
        maxLines: 1,
        suffix: _secretSuffix(colors.textBase, onCopy),
      );
    }

    final copyAffordance = hasValue
        ? HugeIcon(
            icon: HugeIcons.strokeRoundedCopy01,
            size: IconSizes.small,
            color: colors.textBase,
          )
        : null;

    final minLines = widget.minLines;
    final maxLines =
        widget.maxLines ??
        (minLines != null && minLines > _defaultMaxLines
            ? minLines
            : _defaultMaxLines);

    return TextInputComponent(
      label: widget.label,
      focusNode: _focusNode,
      initialValue: widget.value,
      readOnly: true,
      maxLines: maxLines,
      minLines: minLines,
      suffix: copyAffordance,
      onSuffixTap: onCopy,
    );
  }

  Widget _secretSuffix(Color iconColor, VoidCallback? onCopy) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _secretAffordance(
          semanticLabel: _revealed ? 'hide_password' : 'show_password',
          icon: _revealed
              ? HugeIcons.strokeRoundedViewOffSlash
              : HugeIcons.strokeRoundedView,
          color: iconColor,
          onTap: () => setState(() => _revealed = !_revealed),
        ),
        if (onCopy != null) ...[
          const SizedBox(width: Spacing.sm),
          _secretAffordance(
            semanticLabel: 'copy_password',
            icon: HugeIcons.strokeRoundedCopy01,
            color: iconColor,
            onTap: onCopy,
          ),
        ],
      ],
    );
  }

  Widget _secretAffordance({
    required String semanticLabel,
    required List<List<dynamic>> icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: IconSizes.medium,
          height: 48,
          child: Center(
            child: HugeIcon(icon: icon, size: IconSizes.small, color: color),
          ),
        ),
      ),
    );
  }
}
