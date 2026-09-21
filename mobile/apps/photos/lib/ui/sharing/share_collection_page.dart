import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/models/api/collection/user.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import 'package:photos/ui/sharing/add_people_sheet.dart';
import 'package:photos/ui/sharing/manage_links_widget.dart';
import 'package:photos/ui/sharing/public_link_enabled_actions_widget.dart';
import 'package:photos/ui/sharing/share_components.dart';
import 'package:photos/ui/sharing/widgets/participant_role_row.dart';
import 'package:photos/ui/sharing/widgets/participant_row.dart';
import 'package:photos/ui/sharing/widgets/sharing_role.dart';

class ShareCollectionPage extends StatefulWidget {
  final Collection collection;

  const ShareCollectionPage(this.collection, {super.key});

  @override
  State<ShareCollectionPage> createState() => _ShareCollectionPageState();
}

class _ShareCollectionPageState extends State<ShareCollectionPage> {
  late Collection _collection;
  final CollectionActions collectionActions = CollectionActions(
    CollectionsService.instance,
  );
  final GlobalKey sendLinkButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _collection = widget.collection;
  }

  Future<void> _refreshCollection() async {
    try {
      final latest = await CollectionsService.instance.fetchCollectionByID(
        _collection.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _collection = latest;
      });
    } catch (_) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _navigateToAddUser() async {
    await showAddPeopleSheet(context, [_collection]);
    await _refreshCollection();
  }

  @override
  Widget build(BuildContext context) {
    final int userID = Configuration.instance.getUserID() ?? -1;
    final bool hasUrl = _collection.hasLink;
    final bool isOwner = _collection.owner.id == userID;
    if (isOwner && _collection.owner.email.isEmpty) {
      _collection.owner.email = Configuration.instance.getEmail() ?? "";
    }
    final sortedSharees = sortedCollectionSharees(_collection);
    final children = <Widget>[ShareSectionTitle(context.strings.sharedWith)];

    if (isOwner) {
      children.addAll([
        if (sortedSharees.isNotEmpty)
          _participantRoster(userID, sortedSharees)
        else ...[
          Center(child: Image.asset("assets/on_device.png")),
          if (!hasUrl)
            ShareSectionDescription(context.strings.emptyAlbumShareMessage),
        ],
        const SizedBox(height: Spacing.sm),
        ButtonComponent(
          label: context.strings.addPerson,
          variant: ButtonComponentVariant.secondary,
          size: ButtonComponentSize.large,
          shouldSurfaceExecutionStates: false,
          onTap: _navigateToAddUser,
        ),
      ]);
    }

    if (isOwner && _collection.type != CollectionType.uncategorized) {
      children.addAll([
        const SizedBox(height: Spacing.xxl),
        ShareSectionTitle(
          hasUrl ? context.strings.publicLink : context.strings.shareALink,
        ),
      ]);
      if (hasUrl) {
        final url = _collection.publicURLs.first;
        children.addAll([
          if (!url.isExpired)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Text(
                url.enableCollect
                    ? context.strings.publicLinkCollectDescription
                    : context.strings.publicLinkViewDescription,
                style: TextStyles.mini.copyWith(
                  color: context.componentColors.textLight,
                ),
              ),
            ),
          PublicLinkEnabledActionsWidget(
            collection: _collection,
            sendLinkButtonKey: sendLinkButtonKey,
            additionalItems: [
              ShareMenuItem(
                title: context.strings.linkSettings,
                icon: HugeIcons.strokeRoundedSetting07,
                showChevron: true,
                onTap: () async {
                  unawaited(
                    routeToPage(
                      context,
                      ManageSharedLinkWidget(collection: _collection),
                    ).then((value) {
                      _refreshCollection().ignore();
                    }),
                  );
                },
              ),
            ],
          ),
        ]);
      } else {
        children.addAll([
          ShareMenuItem(
            title: context.strings.createPublicLink,
            subtitle: context.strings.shareWithNonenteUsers,
            icon: HugeIcons.strokeRoundedLink04,
            showChevron: true,
            showOnlyLoadingState: true,
            onTap: () async {
              final bool result = await collectionActions.enableUrl(
                context,
                _collection,
              );
              if (result) {
                await _refreshCollection();
              }
            },
          ),
          const SizedBox(height: Spacing.xxl),
          ShareSectionTitle(context.strings.collectPhotos),
          ShareMenuItem(
            title: context.strings.createCollaborativeLink,
            subtitle: context.strings.collabLinkSectionDescription,
            icon: HugeIcons.strokeRoundedUserGroup,
            showChevron: true,
            showOnlyLoadingState: true,
            onTap: () async {
              final bool result = await collectionActions.enableUrl(
                context,
                _collection,
                enableCollect: true,
              );
              if (result) {
                await _refreshCollection();
              }
            },
          ),
        ]);
      }
    }

    return ShareScaffold(
      title: _collection.displayName,
      subtitle: isOwner && (_collection.hasSharees || _collection.hasLink)
          ? context.strings.sharedByYou
          : null,
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.xl,
      ),
      children: children,
    );
  }

  Widget _participantRoster(int userID, List<User> sortedSharees) {
    final rows = <Widget>[
      for (final sharee in sortedSharees)
        ParticipantRoleRow(
          key: ValueKey(sharee.id),
          collection: _collection,
          user: sharee,
          currentUserID: userID,
          onCollectionChanged: () => setState(() {}),
        ),
    ];
    return ScrollableParticipantRoster(rows: rows);
  }
}
