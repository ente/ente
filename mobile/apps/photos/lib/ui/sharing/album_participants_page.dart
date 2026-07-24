import 'package:collection/collection.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/contacts/contact_identity_resolver.dart';
import "package:photos/ui/sharing/add_participant_page.dart";
import 'package:photos/ui/sharing/manage_album_participant.dart';
import 'package:photos/ui/sharing/public_link_enabled_actions_widget.dart';
import 'package:photos/ui/sharing/share_components.dart';
import 'package:photos/ui/sharing/user_avator_widget.dart';

class AlbumParticipantsPage extends StatefulWidget {
  final Collection collection;

  const AlbumParticipantsPage(this.collection, {super.key});

  @override
  State<AlbumParticipantsPage> createState() => _AlbumParticipantsPageState();
}

class _AlbumParticipantsPageState extends State<AlbumParticipantsPage> {
  late int currentUserID;
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
      if (mounted) {
        setState(() {
          _collection = latest;
        });
      }
    } catch (_) {}
  }

  Future<void> _navigateToManageUser(User user) async {
    if (user.id == currentUserID) {
      return;
    }
    await routeToPage(
      context,
      ManageIndividualParticipant(collection: _collection, user: user),
    );
    await _refreshCollection();
  }

  Future<void> _navigateToAddUser(List<ActionTypesToShow> actions) async {
    await routeToPage(context, AddParticipantPage([_collection], actions));
    await _refreshCollection();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserID = Configuration.instance.getUserID()!;
    final role = _collection.getRole(currentUserID);
    final bool isOwner = role == CollectionParticipantRole.owner;
    final bool isAdmin = role == CollectionParticipantRole.admin;
    final bool canManageParticipants = isOwner || isAdmin;
    final bool hasActivePublicLink =
        _collection.hasLink &&
        !(_collection.publicURLs.firstOrNull?.isExpired ?? true);
    final bool shouldShowPublicLink =
        _collection.type != CollectionType.uncategorized &&
        !isOwner &&
        hasActivePublicLink;
    final int participants = 1 + _collection.getSharees().length;
    final User owner = _collection.owner;
    if (owner.id == currentUserID && owner.email == "") {
      owner.email = Configuration.instance.getEmail()!;
    }
    final List<User> allSharees = _collection.getSharees();
    final List<User> admins = [];
    final List<User> collaborators = [];
    final List<User> viewers = [];
    for (final User sharee in allSharees) {
      if (sharee.isAdmin) {
        admins.add(sharee);
      } else if (sharee.isCollaborator) {
        collaborators.add(sharee);
      } else {
        viewers.add(sharee);
      }
    }
    admins.sort((a, b) => a.email.compareTo(b.email));
    collaborators.sort((a, b) => a.email.compareTo(b.email));
    viewers.sort((a, b) => a.email.compareTo(b.email));
    if (isAdmin && !admins.any((u) => u.id == currentUserID)) {
      admins.insert(
        0,
        User(
          id: currentUserID,
          email: Configuration.instance.getEmail() ?? "",
          role: CollectionParticipantRole.admin.toStringVal(),
        ),
      );
    }

    final children = <Widget>[
      if (shouldShowPublicLink) ...[
        ShareSectionTitle(AppLocalizations.of(context).publicLinkEnabled),
        PublicLinkEnabledActionsWidget(
          collection: _collection,
          sendLinkButtonKey: _sendLinkButtonKey,
        ),
        const SizedBox(height: Spacing.xxl),
      ],
      ShareSectionTitle(AppLocalizations.of(context).albumOwner),
      ShareMenuGroup(
        items: [
          ShareMenuItem(
            title: isOwner
                ? AppLocalizations.of(context).you
                : _nameIfAvailableElseEmail(owner),
            leading: UserAvatarWidget(owner, currentUserID: currentUserID),
            isDisabled: true,
          ),
        ],
      ),
      ..._participantSection(
        context,
        title: AppLocalizations.of(context).admins,
        users: admins,
        currentUserID: currentUserID,
        canManageParticipants: canManageParticipants,
        addTitle: admins.isNotEmpty
            ? AppLocalizations.of(context).addMoreAdmins
            : AppLocalizations.of(context).addAdmin,
        addActions: const [ActionTypesToShow.addAdmin],
        addIcon: HugeIcons.strokeRoundedCrown,
      ),
      ..._participantSection(
        context,
        title: AppLocalizations.of(context).collaborator,
        users: collaborators,
        currentUserID: currentUserID,
        canManageParticipants: canManageParticipants,
        addTitle: collaborators.isNotEmpty
            ? AppLocalizations.of(context).addMore
            : AppLocalizations.of(context).addCollaborator,
        addActions: const [ActionTypesToShow.addCollaborator],
        addIcon: HugeIcons.strokeRoundedUserGroup,
      ),
      ..._participantSection(
        context,
        title: AppLocalizations.of(context).viewer,
        users: viewers,
        currentUserID: currentUserID,
        canManageParticipants: canManageParticipants,
        addTitle: viewers.isNotEmpty
            ? AppLocalizations.of(context).addMore
            : AppLocalizations.of(context).addViewer,
        addActions: const [ActionTypesToShow.addViewer],
        addIcon: HugeIcons.strokeRoundedView,
      ),
      const SizedBox(height: Spacing.xxl),
    ];

    return ShareScaffold(
      title: _collection.displayName,
      subtitle: AppLocalizations.of(
        context,
      ).albumParticipantsCount(count: participants),
      children: children,
    );
  }

  List<Widget> _participantSection(
    BuildContext context, {
    required String title,
    required List<User> users,
    required int currentUserID,
    required bool canManageParticipants,
    required String addTitle,
    required List<ActionTypesToShow> addActions,
    required List<List<dynamic>> addIcon,
  }) {
    if (users.isEmpty && !canManageParticipants) {
      return const [];
    }

    final items = <Widget>[
      for (final user in users)
        ShareMenuItem(
          title: user.id == currentUserID
              ? AppLocalizations.of(context).you
              : _nameIfAvailableElseEmail(user),
          leading: UserAvatarWidget(
            user,
            type: AvatarType.medium,
            currentUserID: currentUserID,
          ),
          showChevron: canManageParticipants && user.id != currentUserID,
          isDisabled: !canManageParticipants || user.id == currentUserID,
          onTap: canManageParticipants && user.id != currentUserID
              ? () async {
                  await _navigateToManageUser(user);
                }
              : null,
        ),
      if (canManageParticipants)
        ShareMenuItem(
          title: addTitle,
          icon: addIcon,
          onTap: () async {
            await _navigateToAddUser(addActions);
          },
        ),
    ];

    return [
      const SizedBox(height: Spacing.xxl),
      ShareSectionTitle(title),
      ShareMenuGroup(items: items),
    ];
  }

  String _nameIfAvailableElseEmail(User user) {
    return resolveDisplayName(user);
  }
}
