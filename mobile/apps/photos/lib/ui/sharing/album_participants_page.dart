import "package:collection/collection.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/db/files_db.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";
import "package:photos/ui/sharing/add_people_sheet.dart";
import "package:photos/ui/sharing/public_link_enabled_actions_widget.dart";
import "package:photos/ui/sharing/share_components.dart";
import "package:photos/ui/sharing/widgets/confirm_sheet.dart";
import "package:photos/ui/sharing/widgets/participant_role_row.dart";
import "package:photos/ui/sharing/widgets/participant_row.dart";
import "package:photos/ui/sharing/widgets/sharing_role.dart";

class AlbumParticipantsPage extends StatefulWidget {
  final Collection collection;

  const AlbumParticipantsPage(this.collection, {super.key});

  @override
  State<AlbumParticipantsPage> createState() => _AlbumParticipantsPageState();
}

class _AlbumParticipantsPageState extends State<AlbumParticipantsPage> {
  late final int currentUserID;
  late Collection _collection;
  final GlobalKey _sendLinkButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    currentUserID = Configuration.instance.getUserID()!;
    _collection = widget.collection;
    _refreshCollection();
  }

  Future<void> _refreshCollection() async {
    try {
      final latest = await collectionsService.fetchCollectionByID(
        widget.collection.id,
      );
      if (!mounted) {
        return;
      }
      setState(() => _collection = latest);
    } catch (_) {}
  }

  Future<void> _navigateToAddUser() async {
    await showAddPeopleSheet(context, [_collection]);
    await _refreshCollection();
  }

  Future<void> _leaveAlbum() async {
    final count = await FilesDB.instance.collectionFileCountForOwner(
      _collection.id,
      currentUserID,
    );
    if (!mounted) {
      return;
    }
    final left = await showDestructiveConfirmSheet(
      context,
      title: context.strings.leaveAlbumTitle(album: _collection.displayName),
      body: context.strings.leaveAlbumBody(count: count),
      actionLabel: context.strings.leaveAlbum,
      onConfirm: () => CollectionsService.instance.leaveAlbum(_collection),
    );
    if (left && mounted) {
      var remainingPops = 2;
      Navigator.of(context).popUntil((route) {
        if (route.isFirst || remainingPops == 0) {
          return true;
        }
        remainingPops--;
        return false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = _collection.getRole(currentUserID);
    final isOwner = role == CollectionParticipantRole.owner;
    final isAdmin = role == CollectionParticipantRole.admin;
    final hasActivePublicLink =
        _collection.hasLink &&
        !(_collection.publicURLs.firstOrNull?.isExpired ?? true);
    final shouldShowPublicLink =
        _collection.type != CollectionType.uncategorized &&
        !isOwner &&
        hasActivePublicLink;
    final owner = _collection.owner;
    if (owner.id == currentUserID && owner.email.isEmpty) {
      owner.email = Configuration.instance.getEmail()!;
    }
    final sortedSharees = sortedCollectionSharees(_collection);
    final participantRows = <Widget>[
      for (final sharee in sortedSharees)
        if (isAdmin && sharee.id != currentUserID)
          ParticipantRoleRow(
            key: ValueKey(sharee.id),
            collection: _collection,
            user: sharee,
            currentUserID: currentUserID,
            onCollectionChanged: () => setState(() {}),
          )
        else
          ParticipantRow(
            user: sharee,
            role: _collection.getRole(sharee.id),
            currentUserID: currentUserID,
          ),
    ];
    final children = <Widget>[
      ShareSectionTitle(context.strings.sharedWith),
      ScrollableParticipantRoster(rows: participantRows),
      if (isAdmin && _collection.type != CollectionType.uncategorized) ...[
        const SizedBox(height: Spacing.sm),
        ButtonComponent(
          label: context.strings.addPerson,
          variant: ButtonComponentVariant.secondary,
          size: ButtonComponentSize.large,
          shouldSurfaceExecutionStates: false,
          onTap: _navigateToAddUser,
        ),
      ],
      if (shouldShowPublicLink) ...[
        const SizedBox(height: Spacing.xxl),
        ShareSectionTitle(context.strings.publicLinkEnabled),
        PublicLinkEnabledActionsWidget(
          collection: _collection,
          sendLinkButtonKey: _sendLinkButtonKey,
        ),
      ],
      const SizedBox(height: Spacing.xxl),
    ];
    final subtitle = _subtitle(context, owner, role);
    return ShareScaffold(
      title: _collection.displayName,
      subtitle: subtitle,
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.xl,
      ),
      actions: isOwner
          ? const []
          : [
              EntePopupMenuButton<int>(
                optionsBuilder: () => [
                  EntePopupMenuOption(
                    value: 0,
                    label: context.strings.leaveAlbum,
                    labelColor: context.componentColors.warning,
                    leadingWidget: HugeIcon(
                      icon: HugeIcons.strokeRoundedLogout05,
                      color: context.componentColors.warning,
                      size: IconSizes.small,
                      strokeWidth: 1.6,
                    ),
                    showDivider: false,
                  ),
                ],
                onSelected: (_) => _leaveAlbum(),
              ),
            ],
      children: children,
    );
  }

  String _subtitle(
    BuildContext context,
    User owner,
    CollectionParticipantRole role,
  ) {
    final sharedBy = context.strings.sharedByOwner(
      owner: resolveDisplayName(owner),
    );
    final roleLine = switch (role) {
      CollectionParticipantRole.viewer => context.strings.youAreViewer,
      CollectionParticipantRole.collaborator =>
        context.strings.youAreCollaborator,
      CollectionParticipantRole.admin => context.strings.youAreAdmin,
      CollectionParticipantRole.unknown ||
      CollectionParticipantRole.owner => null,
    };
    return roleLine == null ? sharedBy : "$sharedBy • $roleLine";
  }
}
