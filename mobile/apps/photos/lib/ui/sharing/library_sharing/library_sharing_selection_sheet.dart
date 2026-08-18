import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_controller.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_role_badge.dart';

class LibrarySharingSelectionSheet extends StatelessWidget {
  const LibrarySharingSelectionSheet({
    required this.controller,
    required this.onApply,
    required this.onStopSharing,
    required this.onShowMixedRoles,
    this.isExpanded = true,
    this.onExpandedChanged,
    super.key,
  });

  final LibrarySharingController controller;
  final Future<void> Function() onApply;
  final Future<void> Function() onStopSharing;
  final VoidCallback onShowMixedRoles;
  final bool isExpanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final sheet = BottomSheetComponent(
      showCloseButton: false,
      borderSide: BorderSide(color: colors.strokeDark),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isExpanded) ...[
            _summary(context),
            const SizedBox(height: Spacing.xl),
            _roleControl(context),
            const SizedBox(height: Spacing.md),
          ],
          ButtonComponent(
            label: controller.isAddingAlbums
                ? context.strings.librarySharingShareAlbumCount(
                    count: controller.selectedCount,
                  )
                : context.strings.save,
            density: ButtonComponentDensity.compact,
            isDisabled: !controller.canApply,
            onTap: onApply,
          ),
          if (controller.canStopSharing) ...[
            const SizedBox(height: Spacing.md),
            ButtonComponent(
              label: context.strings.librarySharingStopSharing,
              variant: ButtonComponentVariant.tertiaryCritical,
              density: ButtonComponentDensity.compact,
              shouldSurfaceExecutionStates: false,
              onTap: onStopSharing,
            ),
          ],
        ],
      ),
    );
    final onChanged = onExpandedChanged;
    if (onChanged == null) {
      return sheet;
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Album selection controls',
      expanded: isExpanded,
      onExpand: isExpanded ? null : () => onChanged(true),
      onCollapse: isExpanded ? () => onChanged(false) : null,
      child: _ExpansionGestureDetector(
        isExpanded: isExpanded,
        onExpandedChanged: onChanged,
        child: sheet,
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final l10n = context.strings;
    final selectableAlbumCount = controller.selectableAlbumCount;
    final allSelected =
        selectableAlbumCount > 0 &&
        controller.selectedCount == selectableAlbumCount;
    final canSelectAll =
        selectableAlbumCount > 0 && !allSelected && !controller.isMutating;
    final selectionButton = SelectionSummaryChipComponent(
      key: const ValueKey('library-sharing-select-all'),
      label: l10n.selectAll,
      icon: const HugeIcon(
        icon: HugeIcons.strokeRoundedTick02,
        size: IconSizes.small,
      ),
      semanticLabel: l10n.selectAll,
      isSelected: allSelected,
      onTap: canSelectAll ? controller.selectAll : null,
    );
    final canClearSelection = controller.hasSelection && !controller.isMutating;
    final selectedCount = SelectionSummaryChipComponent(
      key: const ValueKey('library-sharing-selected-count'),
      label: l10n.selectedCount(count: controller.selectedCount),
      icon: const HugeIcon(
        icon: HugeIcons.strokeRoundedCancel01,
        size: IconSizes.small,
      ),
      semanticLabel: canClearSelection
          ? l10n.unselectAll
          : l10n.selectedCount(count: controller.selectedCount),
      isSelected: controller.hasSelection,
      onTap: canClearSelection ? controller.clearSelection : null,
    );
    final useStackedLayout =
        MediaQuery.textScalerOf(context).scale(TextStyles.body.fontSize ?? 14) >
        20;
    return useStackedLayout
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: selectionButton),
              const SizedBox(height: Spacing.xs),
              Align(alignment: Alignment.centerRight, child: selectedCount),
            ],
          )
        : Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: selectionButton,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: selectedCount,
                ),
              ),
            ],
          );
  }

  Widget _roleControl(BuildContext context) {
    final selectedRole = controller.selectedRole;
    final canEditRole = controller.canEditSelectedRoles;
    final trailing = LibrarySharingRoleSelector(
      role: selectedRole,
      fallbackLabel: context.strings.librarySharingMixed,
      showChevron: canEditRole,
    );
    final menu = MenuComponent(
      title: context.strings.librarySharingRole,
      trailing: trailing,
      isDisabled: !canEditRole,
      onTap: selectedRole == null && canEditRole ? onShowMixedRoles : null,
    );
    return MenuGroupComponent(
      items: [
        if (selectedRole != null && canEditRole)
          EntePopupMenuButton<CollectionParticipantRole>(
            optionsBuilder: () =>
                librarySharingRoleOptions(context, activeRole: selectedRole),
            onSelected: controller.setRoleForSelection,
            child: menu,
          )
        else
          menu,
      ],
    );
  }
}

class _ExpansionGestureDetector extends StatefulWidget {
  const _ExpansionGestureDetector({
    required this.isExpanded,
    required this.onExpandedChanged,
    required this.child,
  });

  final bool isExpanded;
  final ValueChanged<bool> onExpandedChanged;
  final Widget child;

  @override
  State<_ExpansionGestureDetector> createState() =>
      _ExpansionGestureDetectorState();
}

class _ExpansionGestureDetectorState extends State<_ExpansionGestureDetector> {
  double _dragDelta = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onVerticalDragStart: (_) => _dragDelta = 0,
      onVerticalDragUpdate: (details) {
        _dragDelta += details.primaryDelta ?? 0;
      },
      onVerticalDragEnd: (_) => _finishDrag(),
      onVerticalDragCancel: _resetDrag,
      child: widget.child,
    );
  }

  void _finishDrag() {
    if (_dragDelta != 0) {
      final shouldExpand = _dragDelta < 0;
      if (shouldExpand != widget.isExpanded) {
        widget.onExpandedChanged(shouldExpand);
      }
    }
    _resetDrag();
  }

  void _resetDrag() => _dragDelta = 0;
}
