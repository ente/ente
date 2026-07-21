import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_controller.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_role_badge.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_sheets.dart';
import 'package:photos/ui/sharing/library_sharing/library_sharing_strings.dart';

class LibrarySharingSelectionSheet extends StatelessWidget {
  const LibrarySharingSelectionSheet({
    required this.controller,
    required this.onApply,
    required this.onStopSharing,
    required this.onShowMixedRoles,
    super.key,
  });

  final LibrarySharingController controller;
  final Future<void> Function() onApply;
  final Future<void> Function() onStopSharing;
  final VoidCallback onShowMixedRoles;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return BottomSheetComponent(
      showCloseButton: false,
      borderSide: BorderSide(color: colors.strokeDark),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _summary(context),
          const SizedBox(height: Spacing.xl),
          _roleControl(context),
          const SizedBox(height: Spacing.md),
          ButtonComponent(
            label: controller.isAddingAlbums
                ? LibrarySharingStrings.shareAlbumCount(
                    controller.selectedCount,
                  )
                : AppLocalizations.of(context).save,
            density: ButtonComponentDensity.compact,
            isDisabled: !controller.canApply,
            onTap: onApply,
          ),
          if (controller.canStopSharing) ...[
            const SizedBox(height: Spacing.md),
            ButtonComponent(
              label: LibrarySharingStrings.stopSharing,
              variant: ButtonComponentVariant.tertiaryCritical,
              density: ButtonComponentDensity.compact,
              shouldSurfaceExecutionStates: false,
              onTap: onStopSharing,
            ),
          ],
        ],
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allSelected =
        controller.selectableAlbumCount > 0 &&
        controller.selectedCount == controller.selectableAlbumCount;
    final canSelectAll =
        controller.selectableAlbumCount > 0 &&
        !allSelected &&
        !controller.isMutating;
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
      label: LibrarySharingStrings.selectedAlbumCount(controller.selectedCount),
      icon: const HugeIcon(
        icon: HugeIcons.strokeRoundedCancel01,
        size: IconSizes.small,
      ),
      semanticLabel: canClearSelection
          ? l10n.unselectAll
          : LibrarySharingStrings.selectedAlbumCount(controller.selectedCount),
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
    final canEditRole = controller.hasSelection && !controller.isMutating;
    final trailing = LibrarySharingRoleSelector(
      role: selectedRole,
      fallbackLabel: LibrarySharingStrings.mixed,
    );
    final menu = MenuComponent(
      title: LibrarySharingStrings.role,
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
