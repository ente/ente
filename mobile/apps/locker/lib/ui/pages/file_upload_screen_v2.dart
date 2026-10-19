import 'dart:convert';
import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/ui/components/collection_selection_widget.dart';
import 'package:locker/ui/components/text_input_sheet.dart';
import 'package:locker/ui/pages/file_upload_screen.dart';
import 'package:locker/utils/bottom_sheet_illustration.dart';
import 'package:locker/utils/file_icon_utils.dart';
import 'package:path/path.dart' as path;

const _maxShare = 0.35;

enum _FileAction { rename, remove }

class FileUploadScreenV2 extends StatefulWidget {
  final List<File> files;
  final List<Collection> collections;
  final Collection? selectedCollection;

  const FileUploadScreenV2({
    super.key,
    required this.files,
    required this.collections,
    this.selectedCollection,
  });

  @override
  State<FileUploadScreenV2> createState() => _FileUploadScreenV2State();
}

class _FileUploadScreenV2State extends State<FileUploadScreenV2> {
  late final List<File> _files = List.of(widget.files);
  late List<Collection> _collections = List.of(widget.collections);
  final Map<String, String> _fileNames = {};
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    final selected = widget.selectedCollection;
    if (selected != null &&
        (selected.type != CollectionType.uncategorized ||
            !selected.isOwner(Configuration.instance.getUserID()!))) {
      _selectedIds.add(selected.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    final hasFiles = _files.isNotEmpty;
    final selectedCount = _collections
        .where((c) => _selectedIds.contains(c.id))
        .length;

    return PopScope(
      canPop: !hasFiles,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await _confirmDiscard() || !context.mounted) return;
        Navigator.of(context).pop();
      },
      child: MediaQuery.withNoTextScaling(
        child: Scaffold(
          backgroundColor: colors.backgroundBase,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  child: Row(
                    children: [
                      IconButtonComponent(
                        variant: IconButtonComponentVariant.unfilled,
                        shouldSurfaceExecutionStates: false,
                        iconSize: IconSizes.medium,
                        icon: const Icon(Icons.arrow_back),
                        onTap: () => Navigator.maybePop(context),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          l10n.uploadFiles,
                          style: TextStyles.display3.copyWith(
                            color: colors.textBase,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final collections = IgnorePointer(
                          ignoring: !hasFiles,
                          child: AnimatedOpacity(
                            duration: Motion.standard,
                            opacity: hasFiles ? 1 : 0.5,
                            child: LayoutBuilder(
                              builder: (context, constraints) =>
                                  CollectionSelectionWidget(
                                    title: '',
                                    maxHeight: constraints.maxHeight,
                                    collections: _collections,
                                    selectedCollectionIds: _selectedIds,
                                    onToggleCollection: (id) => setState(() {
                                      if (!_selectedIds.remove(id)) {
                                        _selectedIds.add(id);
                                      }
                                    }),
                                    onCollectionsUpdated: (collections) =>
                                        setState(
                                          () => _collections = collections,
                                        ),
                                  ),
                            ),
                          ),
                        );
                        final files = AnimatedSwitcher(
                          duration: Motion.standard,
                          child: hasFiles
                              ? _ScrollCard(
                                  itemCount: _files.length,
                                  itemBuilder: (context, index) {
                                    final file = _files[index];
                                    return MenuComponent(
                                      key: ValueKey(file.path),
                                      title: _nameOf(file),
                                      titleMaxLines: 1,
                                      leading: FileIconUtils.getFileIcon(
                                        context,
                                        _nameOf(file),
                                        backgroundColor: Colors.transparent,
                                        size: IconSizes.small,
                                      ),
                                      trailing: Builder(
                                        builder: (anchor) =>
                                            IconButtonComponent(
                                              variant:
                                                  IconButtonComponentVariant
                                                      .unfilled,
                                              shouldSurfaceExecutionStates:
                                                  false,
                                              icon: const HugeIcon(
                                                icon: HugeIcons
                                                    .strokeRoundedMoreVertical,
                                              ),
                                              onTap: () =>
                                                  _showFileMenu(anchor, file),
                                            ),
                                      ),
                                    );
                                  },
                                )
                              : _EmptyItems(onAdd: _addFiles),
                        );
                        final maxListHeight = BoxConstraints(
                          maxHeight: constraints.maxHeight * _maxShare,
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _SectionLabel(
                                    title: l10n.itemsLabel,
                                    meta: l10n.itemCount(count: _files.length),
                                  ),
                                  const SizedBox(height: Spacing.sm),
                                  Flexible(
                                    child: ConstrainedBox(
                                      constraints: maxListHeight,
                                      child: files,
                                    ),
                                  ),
                                  const SizedBox(height: Spacing.xl),
                                  _SectionLabel(
                                    title: l10n.addToCollections,
                                    meta: selectedCount == 0
                                        ? null
                                        : l10n.selectedCount(
                                            count: selectedCount,
                                          ),
                                  ),
                                  const SizedBox(height: Spacing.xs),
                                  Text(
                                    l10n.uncategorizedUploadHint,
                                    style: TextStyles.mini.copyWith(
                                      color: colors.textLight,
                                    ),
                                  ),
                                  const SizedBox(height: Spacing.sm),
                                  Flexible(
                                    child: ConstrainedBox(
                                      constraints: maxListHeight,
                                      child: collections,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: Spacing.md),
                            ButtonComponent(
                              label: l10n.save,
                              isDisabled: !hasFiles,
                              onTap: _save,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _nameOf(File file) =>
      _fileNames[file.path] ?? path.basename(file.path);

  void _save() {
    Navigator.of(context).pop(
      FileUploadScreenResult(
        files: List.of(_files),
        fileNames: {for (final file in _files) file.path: _nameOf(file)},
        note: '',
        selectedCollections: _collections
            .where((c) => _selectedIds.contains(c.id))
            .toList(),
      ),
    );
  }

  Future<void> _showFileMenu(BuildContext anchor, File file) async {
    final l10n = context.strings;
    final warning = context.componentColors.warning;
    final action = await showEntePopupMenu<_FileAction>(
      context: anchor,
      options: [
        EntePopupMenuOption(
          value: _FileAction.rename,
          label: l10n.rename,
          leadingWidget: const HugeIcon(
            icon: HugeIcons.strokeRoundedEdit02,
            size: IconSizes.small,
          ),
        ),
        EntePopupMenuOption(
          value: _FileAction.remove,
          label: l10n.remove,
          labelColor: warning,
          leadingWidget: HugeIcon(
            icon: HugeIcons.strokeRoundedCancel01,
            color: warning,
            size: IconSizes.small,
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _FileAction.rename:
        await _renameFile(file);
      case _FileAction.remove:
        setState(() {
          _files.remove(file);
          _fileNames.remove(file.path);
        });
      case null:
    }
  }

  Future<void> _addFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    if (result == null || !mounted) return;
    setState(() {
      _files.addAll([
        for (final file in result.files)
          if (file.path != null) File(file.path!),
      ]);
    });
  }

  Future<bool> _confirmDiscard() async {
    final l10n = context.strings;
    final discard = await showBottomSheetComponent<bool>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.discardUploadTitle,
        message: l10n.discardUploadMessage,
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: l10n.discardChanges,
            variant: ButtonComponentVariant.critical,
            onTap: () => Navigator.of(sheetContext).pop(true),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _renameFile(File file) async {
    final l10n = context.strings;
    final currentName = _nameOf(file);
    final extension = path.extension(file.path);
    final baseName = currentName.substring(
      0,
      currentName.length - extension.length,
    );

    String? nameForUpload(String name) {
      if (name == baseName) return currentName;
      var cleaned = name.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '').trim();
      if (extension.isNotEmpty &&
          cleaned.toLowerCase().endsWith(extension.toLowerCase())) {
        cleaned = cleaned
            .substring(0, cleaned.length - extension.length)
            .trim();
      }
      if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return null;
      return '$cleaned$extension';
    }

    await showTextInputSheet(
      context,
      title: l10n.renameFile,
      initialValue: baseName,
      hintText: l10n.enterFileName,
      submitButtonLabel: l10n.save,
      validator: (name) {
        final fileName = nameForUpload(name);
        if (fileName == null) return l10n.enterFileName;
        if (utf8.encode(fileName).length > 255) return l10n.fileNameTooLong;
        return null;
      },
      onSubmit: (name) async {
        final fileName = nameForUpload(name);
        if (fileName == null || !mounted) return;
        setState(() => _fileNames[file.path] = fileName);
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.meta});

  final String title;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyles.large.copyWith(color: colors.textBase),
          ),
        ),
        if (meta != null)
          Text(meta!, style: TextStyles.mini.copyWith(color: colors.textLight)),
      ],
    );
  }
}

class _EmptyItems extends StatelessWidget {
  const _EmptyItems({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(Spacing.xxl),
        decoration: BoxDecoration(
          color: colors.fillLight,
          borderRadius: Radii.buttonBorder,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedFile02,
              color: colors.textLighter,
              size: IconSizes.large,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              l10n.uploadItemsRemoved,
              textAlign: TextAlign.center,
              style: TextStyles.body.copyWith(color: colors.textLight),
            ),
            const SizedBox(height: Spacing.lg),
            ButtonComponent(
              label: l10n.addItems,
              variant: ButtonComponentVariant.secondary,
              leading: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
              shouldSurfaceExecutionStates: false,
              onTap: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollCard extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const _ScrollCard({required this.itemCount, required this.itemBuilder});

  @override
  State<_ScrollCard> createState() => _ScrollCardState();
}

class _ScrollCardState extends State<_ScrollCard> {
  final _controller = ScrollController();
  bool _hasMore = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onScroll(Notification notification) {
    if (notification
        case ScrollMetricsNotification(:final metrics) ||
            ScrollUpdateNotification(:final metrics)) {
      final hasMore = metrics.extentAfter > 0;
      if (hasMore != _hasMore) setState(() => _hasMore = hasMore);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border.all(color: colors.strokeFaint),
        borderRadius: Radii.buttonBorder,
      ),
      child: ClipRRect(
        borderRadius: Radii.buttonBorder,
        child: NotificationListener<Notification>(
          onNotification: _onScroll,
          child: Stack(
            children: [
              Scrollbar(
                controller: _controller,
                child: ListView.separated(
                  controller: _controller,
                  physics: const ClampingScrollPhysics(),
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: widget.itemCount,
                  separatorBuilder: (_, _) => ColoredBox(
                    color: colors.fillLight,
                    child: const DividerComponent(),
                  ),
                  itemBuilder: (context, index) => MenuGroupComponent(
                    borderRadius: MenuGroupComponent.itemBorderRadius(
                      index: index,
                      itemCount: widget.itemCount,
                    ),
                    items: [widget.itemBuilder(context, index)],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: Spacing.xxl,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _hasMore ? 1 : 0,
                    duration: Motion.quick,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colors.fillLight.withValues(alpha: 0),
                            colors.fillLight,
                          ],
                        ),
                      ),
                    ),
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
