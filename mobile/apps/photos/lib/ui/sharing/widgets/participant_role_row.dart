import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/db/files_db.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/sharing/widgets/confirm_sheet.dart";
import "package:photos/ui/sharing/widgets/participant_row.dart";
import "package:photos/ui/sharing/widgets/sharing_role.dart";

enum _ParticipantRoleAction {
  viewer(CollectionParticipantRole.viewer),
  collaborator(CollectionParticipantRole.collaborator),
  admin(CollectionParticipantRole.admin),
  remove(null);

  const _ParticipantRoleAction(this.role);

  final CollectionParticipantRole? role;
}

class ParticipantRoleRow extends StatefulWidget {
  const ParticipantRoleRow({
    super.key,
    required this.collection,
    required this.user,
    required this.currentUserID,
    required this.onCollectionChanged,
  });

  final Collection collection;
  final User user;
  final int currentUserID;
  final VoidCallback onCollectionChanged;

  @override
  State<ParticipantRoleRow> createState() => _ParticipantRoleRowState();
}

class _ParticipantRoleRowState extends State<ParticipantRoleRow> {
  bool _isChangingRole = false;

  @override
  Widget build(BuildContext context) {
    final role = widget.collection.getRole(widget.user.id);
    return ParticipantRow(
      user: widget.user,
      role: role,
      currentUserID: widget.currentUserID,
      trailing: _isChangingRole
          ? SizedBox.square(
              dimension: IconSizes.small,
              child: CircularProgressIndicator(
                color: context.componentColors.textLight,
                strokeWidth: 2,
              ),
            )
          : EntePopupMenuButton<_ParticipantRoleAction>(
              optionsBuilder: () => _options(context),
              onSelected: (action) => action == _ParticipantRoleAction.remove
                  ? _removeParticipant()
                  : _changeRole(action.role!),
              child: HugeIcon(
                icon: albumSharingRoleIcon(role),
                color: context.componentColors.textBase,
                size: IconSizes.small,
                strokeWidth: 1.6,
              ),
            ),
    );
  }

  List<EntePopupMenuOption<_ParticipantRoleAction>> _options(
    BuildContext context,
  ) {
    final colors = context.componentColors;
    final activeRole = widget.collection.getRole(widget.user.id);
    return [
      for (final action in _ParticipantRoleAction.values)
        if (action.role case final role?)
          EntePopupMenuOption(
            value: action,
            label: shareableRoleLabel(context, role),
            leadingWidget: HugeIcon(
              icon: albumSharingRoleIcon(role),
              size: IconSizes.small,
            ),
            isActive: role == activeRole,
          ),
      EntePopupMenuOption(
        value: _ParticipantRoleAction.remove,
        label: context.strings.remove,
        labelColor: colors.warning,
        leadingWidget: HugeIcon(
          icon: HugeIcons.strokeRoundedDelete02,
          color: colors.warning,
          size: IconSizes.small,
        ),
        showDivider: false,
      ),
    ];
  }

  Future<void> _changeRole(CollectionParticipantRole role) async {
    if (role == widget.collection.getRole(widget.user.id)) {
      return;
    }
    setState(() => _isChangingRole = true);
    final actions = CollectionActions(CollectionsService.instance);
    final result = await actions.addEmailToCollection(
      widget.collection,
      widget.user.email,
      role,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isChangingRole = false);
    if (!result.succeeded) {
      await actions.showAddEmailToCollectionFailure(context, result);
      return;
    }
    widget.onCollectionChanged();
  }

  Future<void> _removeParticipant() async {
    final count = await FilesDB.instance.collectionFileCountForOwner(
      widget.collection.id,
      widget.user.id,
    );
    if (!mounted) {
      return;
    }
    final removed = await showDestructiveConfirmSheet(
      context,
      title: context.strings.removePersonTitle(
        name: resolveDisplayName(widget.user),
      ),
      body: context.strings.removePersonBody(count: count),
      actionLabel: context.strings.removeParticipant,
      onConfirm: () async {
        final sharees = await CollectionsService.instance.unshare(
          widget.collection.id,
          widget.user.email,
        );
        widget.collection.updateSharees(sharees);
      },
    );
    if (removed && mounted) {
      widget.onCollectionChanged();
    }
  }
}
