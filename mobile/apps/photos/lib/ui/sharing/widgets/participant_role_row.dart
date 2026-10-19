import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/db/files_db.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/sharing/widgets/confirm_sheet.dart";
import "package:photos/ui/sharing/widgets/participant_role_sheet.dart";
import "package:photos/ui/sharing/widgets/participant_row.dart";

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
  bool _isShowingOptions = false;

  @override
  Widget build(BuildContext context) {
    final role = widget.collection.getRole(widget.user.id);
    return ParticipantRow(
      user: widget.user,
      role: role,
      currentUserID: widget.currentUserID,
      onTap: _isChangingRole ? null : _showOptions,
      onLongPress: _isChangingRole ? null : _showOptions,
      trailing: _isChangingRole
          ? SizedBox.square(
              dimension: IconSizes.small,
              child: CircularProgressIndicator(
                color: context.componentColors.textLight,
                strokeWidth: 2,
              ),
            )
          : IconButtonComponent(
              icon: const Icon(Icons.more_horiz),
              tooltip: context.strings.moreOptions,
              variant: IconButtonComponentVariant.unfilled,
              size: 48,
              shouldSurfaceExecutionStates: false,
              onTap: _showOptions,
            ),
    );
  }

  Future<void> _showOptions() async {
    if (_isShowingOptions || _isChangingRole) return;
    _isShowingOptions = true;
    try {
      final action = await showParticipantRoleSheet(
        context,
        email: widget.user.email,
        currentRole: widget.collection.getRole(widget.user.id),
      );
      if (!mounted || action == null) return;
      await _onSelected(action);
    } finally {
      _isShowingOptions = false;
    }
  }

  Future<void> _onSelected(ParticipantRoleAction action) =>
      action == ParticipantRoleAction.remove
      ? _removeParticipant()
      : _changeRole(action.role!);

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
