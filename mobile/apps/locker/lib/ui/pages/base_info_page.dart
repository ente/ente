import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/utils/toast_util.dart';
import "package:ente_utils/email_util.dart";
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:locker/core/errors.dart';
import 'package:locker/events/user_details_refresh_event.dart';
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

  T? _currentData;

  List<Collection> _availableCollections = [];
  Set<int> _selectedCollectionIds = {};
  Set<int> _initialSelectedCollectionIds = {};
  bool _hasLoadedCollectionSelection = false;

  T? get currentData {
    if (_currentData != null) {
      return _currentData;
    }

    if (widget.existingFile != null) {
      final infoItem = InfoFileService.instance.extractInfoFromFile(
        widget.existingFile!,
      );
      return infoItem?.data as T?;
    }

    return null;
  }

  void refreshUIWithCurrentData() {}

  String get pageTitle;
  String get submitButtonText;
  InfoType get infoType;
  T createInfoData();
  List<Widget> buildFormFields();
  List<Widget> buildViewFields();
  bool validateForm();

  @protected
  bool get hasUnsavedChanges;

  @protected
  String get discardChangesDescription =>
      context.strings.unsavedChangesDescription;

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
    final hasCollectionChanges = !setEquals(
      _selectedCollectionIds,
      _initialSelectedCollectionIds,
    );
    if (!hasUnsavedChanges && !hasCollectionChanges) {
      return true;
    }

    final shouldDiscard = await _showDiscardChangesDialog();
    if (!shouldDiscard) {
      return false;
    }

    _restoreEditSession();
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
            title: showCollectionSelectionTitle
                ? context.strings.collections
                : '',
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

  void loadExistingData() {}

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
        _initialSelectedCollectionIds = Set<int>.of(initialSelection);
        _hasLoadedCollectionSelection = true;
      });
    } catch (e) {
      // Leave collection selection unavailable.
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
      final infoData = createInfoData();
      final infoItem = InfoItem(
        type: infoType,
        data: infoData,
        createdAt: DateTime.now(),
      );

      if (widget.existingFile != null) {
        await _updateExistingFile(infoItem);
      } else {
        await _createNewFile(infoItem);
      }

      if (mounted && widget.existingFile != null) {
        _captureEditSessionState();

        setState(() {
          _currentMode = InfoPageMode.view;
        });

        showToast(context, context.strings.recordSavedSuccessfully);
      }
    } on StorageLimitExceededError {
      if (mounted) {
        showToast(context, context.strings.uploadStorageLimitErrorBody);
      }
    } on NoActiveSubscriptionError {
      if (mounted) {
        await _showUploadErrorSheet(
          context.strings.uploadSubscriptionExpiredErrorTitle,
          context.strings.uploadSubscriptionExpiredErrorBody,
        );
      }
    } on FileLimitReachedError {
      if (mounted) {
        showToast(context, context.strings.uploadFileCountLimitErrorToast);
      }
    } catch (e) {
      if (mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
  }

  Future<void> _updateExistingFile(InfoItem infoItem) async {
    if (widget.existingFile == null) return;

    // updateInfoFile syncs internally.
    final success = await InfoFileService.instance.updateInfoFile(
      existingFile: widget.existingFile!,
      updatedInfoItem: infoItem,
    );

    if (!success) {
      throw Exception('Failed to update file metadata');
    }

    await _updateCollectionMembership();

    if (!mounted) return;

    setState(() {
      _currentData = infoItem.data as T?;
    });

    refreshUIWithCurrentData();
  }

  Future<void> _updateCollectionMembership() async {
    if (widget.existingFile == null) return;
    if (!_hasLoadedCollectionSelection) return;

    final currentCollections = await CollectionService.instance
        .getCollectionsForFile(widget.existingFile!);

    final allCollections = await CollectionService.instance.getCollections();

    final favoriteCollection = await CollectionService.instance
        .getOrCreateImportantCollection();

    final currentCollectionIds = currentCollections.map((c) => c.id).toSet();

    final wasFavorite = currentCollectionIds.contains(favoriteCollection.id);
    final isFavoriteNow = _selectedCollectionIds.contains(
      favoriteCollection.id,
    );

    if (wasFavorite && !isFavoriteNow) {
      await FavoritesService.instance.removeFromFavorites(widget.existingFile!);
    } else if (!wasFavorite && isFavoriteNow) {
      await FavoritesService.instance.addToFavorites(widget.existingFile!);
    }

    // Only Favorites is special. Uncategorized changes only when selected or
    // deselected like any other collection.
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

    final uploadedFile = await InfoFileService.instance.createAndUploadInfoFile(
      infoItem: infoItem,
      collection: selectedCollections.first,
    );

    for (int i = 1; i < selectedCollections.length; i++) {
      await CollectionService.instance.addToCollection(
        selectedCollections[i],
        uploadedFile,
        runSync: false,
      );
    }

    await CollectionService.instance.sync();
    Bus.instance.fire(UserDetailsRefreshEvent());

    if (!mounted) return;

    final collectionCount = selectedCollections.length;
    final message = collectionCount == 1
        ? context.strings.recordSavedSuccessfully
        : context.strings.recordSavedToMultipleCollections(
            count: collectionCount,
          );

    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const HomePage()),
      (route) => false,
    );

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
            label: context.strings.contactSupport,
            onTap: () async {
              await sendEmail(context, to: "support@ente.com", body: message);
            },
          ),
        ],
      ),
    );
  }

  void _toggleMode() {
    if (isInViewMode) {
      _captureEditSessionState();
    }

    setState(() {
      _currentMode = _currentMode == InfoPageMode.view
          ? InfoPageMode.edit
          : InfoPageMode.view;
    });
  }

  void _copyToClipboard(String text, String fieldName) {
    Clipboard.setData(ClipboardData(text: text));
    showToast(
      context,
      context.strings.fieldCopiedToClipboard(fieldName: fieldName),
    );
  }

  void _captureEditSessionState() {
    _initialSelectedCollectionIds = Set<int>.of(_selectedCollectionIds);
  }

  void _restoreEditSession() {
    loadExistingData();
    setState(() {
      _selectedCollectionIds = Set<int>.of(_initialSelectedCollectionIds);
    });
  }

  Future<bool> _showDiscardChangesDialog() async {
    final result = await showBottomSheetComponent<bool>(
      context: context,
      builder: (_) => BottomSheetComponent(
        title: context.strings.unsavedNoteChangesTitle,
        message: discardChangesDescription,
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.strings.discardChanges,
            variant: ButtonComponentVariant.critical,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    return result ?? false;
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
                        tooltip: context.strings.edit,
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
                      shouldShowSuccessState: false,
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
