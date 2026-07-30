import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/services/library_sharing_service.dart';

List<EntePopupMenuOption<CollectionParticipantRole>> librarySharingRoleOptions(
  BuildContext context, {
  CollectionParticipantRole? activeRole,
}) {
  return [
    for (final role in librarySharingRoles)
      EntePopupMenuOption(
        value: role,
        label: librarySharingRoleLabel(context, role),
        leadingWidget: HugeIcon(
          icon: librarySharingRoleIcon(role),
          size: IconSizes.small,
          strokeWidth: 1.6,
        ),
        isActive: role == activeRole,
        activeTrailingWidget: const HugeIcon(
          icon: HugeIcons.strokeRoundedTick02,
          size: IconSizes.small,
        ),
      ),
  ];
}

class LibrarySharingRoleBadge extends StatelessWidget {
  const LibrarySharingRoleBadge({required this.role, super.key});

  final CollectionParticipantRole role;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final label = librarySharingRoleLabel(context, role);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 20,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.fillLight,
            borderRadius: BorderRadius.circular(40),
          ),
          child: Center(
            child: HugeIcon(
              icon: librarySharingRoleIcon(role),
              size: IconSizes.micro,
              color: colors.textBase,
              strokeWidth: 1.8,
            ),
          ),
        ),
      ),
    );
  }
}

class LibrarySharingRoleSelector extends StatelessWidget {
  const LibrarySharingRoleSelector({
    required this.role,
    this.fallbackLabel,
    super.key,
  }) : assert(role != null || fallbackLabel != null);

  final CollectionParticipantRole? role;
  final String? fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: Spacing.lg, right: Spacing.md),
      decoration: BoxDecoration(
        color: colors.fillDark,
        borderRadius: BorderRadius.circular(Radii.button),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (role != null) ...[
            HugeIcon(
              icon: librarySharingRoleIcon(role!),
              size: IconSizes.small,
              color: colors.textBase,
              strokeWidth: 1.8,
            ),
            const SizedBox(width: Spacing.xs),
          ],
          Text(
            role == null
                ? fallbackLabel!
                : librarySharingRoleLabel(context, role!),
            style: TextStyles.mini.copyWith(color: colors.textBase),
          ),
          const SizedBox(width: Spacing.sm),
          const HugeIcon(
            icon: HugeIcons.strokeRoundedArrowDown01,
            size: IconSizes.small,
          ),
        ],
      ),
    );
  }
}

List<List<dynamic>> librarySharingRoleIcon(CollectionParticipantRole role) {
  return switch (role) {
    CollectionParticipantRole.admin => HugeIcons.strokeRoundedCrown02,
    CollectionParticipantRole.collaborator => HugeIcons.strokeRoundedUserGroup,
    _ => HugeIcons.strokeRoundedView,
  };
}

String librarySharingRoleLabel(
  BuildContext context,
  CollectionParticipantRole role,
) {
  final l10n = AppLocalizations.of(context);
  return switch (role) {
    CollectionParticipantRole.admin => l10n.admin,
    CollectionParticipantRole.collaborator => l10n.collaborator,
    _ => l10n.viewer,
  };
}
