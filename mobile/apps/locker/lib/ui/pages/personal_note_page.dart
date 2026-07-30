import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:locker/l10n/l10n.dart';
import 'package:locker/models/info/info_item.dart';
import 'package:locker/ui/components/collection_selection_widget.dart';
import 'package:locker/ui/pages/base_info_page.dart';
import "package:locker/utils/bottom_sheet_illustration.dart";

class PersonalNotePage extends BaseInfoPage<PersonalNoteData> {
  const PersonalNotePage({
    super.key,
    super.mode = InfoPageMode.edit,
    super.existingFile,
    super.onCancelWithoutSaving,
  });

  @override
  State<PersonalNotePage> createState() => _PersonalNotePageState();
}

class _PersonalNotePageState
    extends BaseInfoPageState<PersonalNoteData, PersonalNotePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _contentFocusNode = FocusNode();
  bool _isControllerSyncInProgress = false;
  String _initialTitle = '';
  String _initialContent = '';

  @override
  void initState() {
    super.initState();
    _contentController.addListener(_onContentChanged);
  }

  @override
  void loadExistingData() {
    _syncControllers(triggerSetState: false, updateInitial: true);
  }

  @override
  void refreshUIWithCurrentData() {
    super.refreshUIWithCurrentData();
    _syncControllers(triggerSetState: true, updateInitial: true);
  }

  @override
  void dispose() {
    _contentController.removeListener(_onContentChanged);
    _nameController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  @override
  String get pageTitle {
    if (isInEditMode) {
      return context.l10n.note;
    }

    final controllerTitle = _nameController.text.trim();
    if (controllerTitle.isNotEmpty) {
      return controllerTitle;
    }

    final dataTitle = (currentData?.title ?? '').trim();
    if (dataTitle.isNotEmpty) {
      return dataTitle;
    }

    return context.l10n.personalNote;
  }

  @override
  String get submitButtonText => context.l10n.saveRecord;

  @override
  InfoType get infoType => InfoType.note;

  @override
  bool validateForm() {
    final content = _contentController.text.trim();
    return content.isNotEmpty;
  }

  @override
  PersonalNoteData createInfoData() {
    final content = _contentController.text.trim();
    var title = _nameController.text.trim();

    if (title.isEmpty && content.isNotEmpty) {
      title = _generateTitleFromContent(content);
    }

    return PersonalNoteData(title: title, content: content);
  }

  String _generateTitleFromContent(
    String content, {
    int maxWords = 5,
    int maxLength = 40,
  }) {
    final firstLine = content.split('\n').first.trim();
    if (firstLine.isEmpty) return '';

    final words = firstLine.split(RegExp(r'\s+'));
    final limitedWords = words.take(maxWords).join(' ');

    if (limitedWords.length <= maxLength) {
      return limitedWords;
    }
    return '${limitedWords.substring(0, maxLength).trimRight()}...';
  }

  @override
  List<Widget> buildFormFields() => const <Widget>[];

  @override
  List<Widget> buildViewFields() {
    if (_contentController.text.trim().isEmpty) {
      return const <Widget>[];
    }
    return [
      buildViewField(
        label: context.l10n.noteContent,
        value: _contentController.text,
        minLines: 12,
        maxLines: 24,
      ),
    ];
  }

  @override
  Widget buildEditModeContent(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      sliver: SliverList.list(
        children: [
          TextInputComponent(
            label: context.l10n.noteName,
            hintText: context.l10n.noteNameHint,
            controller: _nameController,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            shouldUnfocusOnClearOrSubmit: true,
          ),
          const SizedBox(height: 24),
          TextInputComponent(
            label: context.l10n.noteContent,
            hintText: context.l10n.noteContentHint,
            controller: _contentController,
            focusNode: _contentFocusNode,
            isRequired: true,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            minLines: 12,
            maxLines: 12,
          ),
          SizedBox(height: collectionSpacing),
          CollectionSelectionWidget(
            collections: availableCollections,
            selectedCollectionIds: selectedCollectionIds,
            onToggleCollection: toggleCollectionSelection,
            onCollectionsUpdated: updateAvailableCollections,
            title: showCollectionSelectionTitle ? context.l10n.collections : '',
          ),
        ],
      ),
    );
  }

  @override
  double get viewModeBottomPadding => 100;

  void _syncControllers({
    bool triggerSetState = true,
    bool updateInitial = false,
  }) {
    _isControllerSyncInProgress = true;
    try {
      final data = currentData;
      _nameController.text = data?.title ?? '';
      _contentController.text = data?.content ?? '';
      if (updateInitial) {
        _initialTitle = _nameController.text;
        _initialContent = _contentController.text;
      }
    } finally {
      _isControllerSyncInProgress = false;
    }

    if (triggerSetState && mounted) {
      setState(() {});
    }
  }

  void _onContentChanged() {
    if (_isControllerSyncInProgress) {
      return;
    }
    onFieldChanged();
  }

  bool get _hasUnsavedChanges {
    return _contentController.text.trim() != _initialContent.trim() ||
        _nameController.text.trim() != _initialTitle.trim();
  }

  @override
  Future<bool> onEditModeBackPressed() async {
    if (!_hasUnsavedChanges) {
      return true;
    }

    final shouldDiscard = await _showDiscardChangesDialog();
    if (!shouldDiscard) {
      return false;
    }

    _syncControllers(triggerSetState: true, updateInitial: false);
    return true;
  }

  Future<bool> _showDiscardChangesDialog() async {
    final result = await showBottomSheetComponent<bool>(
      context: context,
      builder: (_) => BottomSheetComponent(
        title: context.l10n.unsavedNoteChangesTitle,
        message: context.l10n.unsavedNoteChangesDescription,
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.l10n.discardChanges,
            variant: ButtonComponentVariant.critical,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}
