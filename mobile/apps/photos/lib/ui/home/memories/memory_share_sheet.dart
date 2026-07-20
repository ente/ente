import "dart:math" as math;

import "package:ente_components/components/chip_surface.dart";
import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/boundary_reporter_mixin.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";

enum MemoryShareSheetAction { shareMemory, shareItems }

class MemoryShareSheetResult {
  final MemoryShareSheetAction action;
  final List<Memory> selectedMemories;

  MemoryShareSheetResult({
    required this.action,
    required List<Memory> selectedMemories,
  }) : selectedMemories = List.unmodifiable(selectedMemories);
}

Future<MemoryShareSheetResult?> showMemoryShareSelectionSheet(
  BuildContext context, {
  required List<Memory> memories,
  required int initialIndex,
  required bool canShareMemoryLink,
}) {
  return showBottomSheetComponent<MemoryShareSheetResult>(
    context: context,
    builder: (_) => _MemoryShareSelectionSheet(
      memories: memories,
      initialIndex: initialIndex,
      canShareMemoryLink: canShareMemoryLink,
    ),
  );
}

class _MemoryShareSelectionSheet extends StatefulWidget {
  final List<Memory> memories;
  final int initialIndex;
  final bool canShareMemoryLink;

  const _MemoryShareSelectionSheet({
    required this.memories,
    required this.initialIndex,
    required this.canShareMemoryLink,
  });

  @override
  State<_MemoryShareSelectionSheet> createState() =>
      _MemoryShareSelectionSheetState();
}

class _MemoryShareSelectionSheetState
    extends State<_MemoryShareSelectionSheet> {
  late final List<Memory> _memories = List.unmodifiable(widget.memories);
  late final _files = _memories
      .map((memory) => memory.file)
      .toList(growable: false);
  late final SelectedFiles _selectedFiles;

  bool get _hasSelection => _selectedFiles.files.isNotEmpty;

  bool get _areAllSelected => _files.every(_selectedFiles.isFileSelected);

  List<Memory> get _orderedSelection => _memories
      .where((memory) => _selectedFiles.isFileSelected(memory.file))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _selectedFiles = SelectedFiles()
      ..selectAll({_memories[widget.initialIndex].file})
      ..addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _selectedFiles.dispose();
    super.dispose();
  }

  void _onSelectionChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = math.min(screenHeight * 0.792, screenHeight - 80);

    return SizedBox(
      height: sheetHeight,
      child: GalleryBoundariesProvider(
        child: BottomSheetComponent(
          header: _MemoryShareSheetBoundary(
            position: BoundaryPosition.top,
            child: _buildHeader(context, l10n),
          ),
          showCloseButton: false,
          padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
          content: Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                  child: _buildSelectionControls(context, l10n),
                ),
                const SizedBox(height: Spacing.lg),
                Expanded(child: _buildGrid()),
              ],
            ),
          ),
          actions: _buildActions(l10n),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final colors = context.componentColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.shareMemory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyles.h1.copyWith(color: colors.textBase),
              ),
            ),
            const SizedBox(width: Spacing.md),
            IconButtonComponent(
              key: const ValueKey("memory-share-close"),
              tooltip: l10n.close,
              variant: IconButtonComponentVariant.circular,
              shouldSurfaceExecutionStates: false,
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedCancel01,
                size: IconSizes.small,
              ),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionControls(BuildContext context, AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSelectionChip(
          key: const ValueKey("memory-share-selected-count"),
          label: l10n.selectedPhotos(count: _selectedFiles.files.length),
          icon: HugeIcons.strokeRoundedCancel01,
          semanticLabel: l10n.clearSelection,
          selected: _hasSelection,
          onTap: _hasSelection ? _clearSelection : null,
        ),
        _buildSelectionChip(
          key: const ValueKey("memory-share-select-all"),
          label: l10n.selectAll,
          icon: HugeIcons.strokeRoundedTick02,
          semanticLabel: l10n.selectAll,
          selected: _areAllSelected,
          onTap: _areAllSelected ? null : _selectAll,
        ),
      ],
    );
  }

  Widget _buildSelectionChip({
    required Key key,
    required String label,
    required List<List<dynamic>> icon,
    required String semanticLabel,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final colors = context.componentColors;
    final foreground = onTap == null ? colors.textLighter : colors.textBase;
    return ChipSurface(
      key: key,
      surfaceKey: ValueKey("$key-surface"),
      enabled: onTap != null,
      selected: selected,
      semanticLabel: semanticLabel,
      minWidth: 104,
      minHeight: 36,
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 8, Spacing.md, 8),
      background: colors.fillLight,
      borderRadius: BorderRadius.circular(100),
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 66,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyles.mini.copyWith(color: foreground),
            ),
          ),
          const SizedBox(width: Spacing.xs),
          ChipIconSlot(
            color: foreground,
            size: 12,
            slotSize: 14,
            child: HugeIcon(icon: icon),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return GalleryFilesState(
      child: Gallery(
        initialFiles: _files,
        asyncLoader: (_, _, {limit, asc}) async =>
            FileLoadResult(_files, false),
        tagPrefix: "memory_share_gallery",
        selectedFiles: _selectedFiles,
        enableFileGrouping: false,
        inSelectionMode: true,
        showSelectAll: false,
        disablePinnedGroupHeader: true,
        disableVerticalPaddingForScrollbar: true,
        footer: const SizedBox.shrink(),
      ),
    );
  }

  List<Widget> _buildActions(AppLocalizations l10n) {
    return [
      _MemoryShareSheetBoundary(
        position: BoundaryPosition.bottom,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.canShareMemoryLink) ...[
              _buildAction(
                l10n.shareMemory,
                MemoryShareSheetAction.shareMemory,
              ),
              const SizedBox(height: Spacing.md),
            ],
            _buildAction(
              l10n.shareItemCount(count: _selectedFiles.files.length),
              MemoryShareSheetAction.shareItems,
              variant: widget.canShareMemoryLink
                  ? ButtonComponentVariant.secondary
                  : ButtonComponentVariant.primary,
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildAction(
    String label,
    MemoryShareSheetAction action, {
    ButtonComponentVariant variant = ButtonComponentVariant.primary,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: ButtonComponent(
        label: label,
        variant: variant,
        isDisabled: !_hasSelection,
        shouldSurfaceExecutionStates: false,
        onTap: _hasSelection ? () => _complete(action) : null,
      ),
    );
  }

  void _clearSelection() => _selectedFiles.clearAll(fireEvent: false);

  void _selectAll() => _selectedFiles.replaceSelection(_files.toSet());

  void _complete(MemoryShareSheetAction action) {
    Navigator.of(context).pop(
      MemoryShareSheetResult(
        action: action,
        selectedMemories: _orderedSelection,
      ),
    );
  }
}

class _MemoryShareSheetBoundary extends StatefulWidget {
  final BoundaryPosition position;
  final Widget child;

  const _MemoryShareSheetBoundary({
    required this.position,
    required this.child,
  });

  @override
  State<_MemoryShareSheetBoundary> createState() =>
      _MemoryShareSheetBoundaryState();
}

class _MemoryShareSheetBoundaryState extends State<_MemoryShareSheetBoundary>
    with BoundaryReporter {
  @override
  Widget build(BuildContext context) {
    return boundaryWidget(position: widget.position, child: widget.child);
  }
}
