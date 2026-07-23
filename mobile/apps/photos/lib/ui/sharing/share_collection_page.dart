import 'dart:async';

import 'package:collection/collection.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/api/collection/user.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/contacts/contact_identity_resolver.dart';
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import 'package:photos/ui/sharing/add_participant_page.dart';
import 'package:photos/ui/sharing/album_participants_page.dart';
import 'package:photos/ui/sharing/album_share_info_widget.dart';
import 'package:photos/ui/sharing/manage_album_participant.dart';
import 'package:photos/ui/sharing/manage_links_widget.dart';
import 'package:photos/ui/sharing/public_link_enabled_actions_widget.dart';
import 'package:photos/ui/sharing/share_components.dart';
import 'package:photos/ui/sharing/user_avator_widget.dart';

class ShareCollectionPage extends StatefulWidget {
  final Collection collection;

  const ShareCollectionPage(this.collection, {super.key});

  @override
  State<ShareCollectionPage> createState() => _ShareCollectionPageState();
}

class _ShareCollectionPageState extends State<ShareCollectionPage> {
  late Collection _collection;
  late List<User?> _sharees;
  final CollectionActions collectionActions = CollectionActions(
    CollectionsService.instance,
  );
  final GlobalKey sendLinkButtonKey = GlobalKey();
  bool _redirectedToParticipants = false;

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

  Future<void> _navigateToManageUser() async {
    if (_sharees.length == 1) {
      await routeToPage(
        context,
        ManageIndividualParticipant(
          collection: _collection,
          user: _sharees.first!,
        ),
      );
    } else {
      await routeToPage(context, AlbumParticipantsPage(_collection));
    }
    await _refreshCollection();
  }

  @override
  Widget build(BuildContext context) {
    final int userID = Configuration.instance.getUserID() ?? -1;

    if (!_redirectedToParticipants) {
      final bool isOwner = _collection.owner.id == userID;
      if (!isOwner) {
        _redirectedToParticipants = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          replacePage(context, AlbumParticipantsPage(_collection));
        });
      } else {
        _redirectedToParticipants = true;
      }
    }

    _sharees = _collection.sharees;
    final bool hasUrl = _collection.hasLink;
    final bool isOwner = _collection.owner.id == userID;
    final bool canManageParticipants = isOwner;
    final children = <Widget>[
      ShareSectionTitle(
        AppLocalizations.of(
          context,
        ).shareWithPeopleSectionTitle(numberOfPeople: _sharees.length),
      ),
      EmailItemWidget(_collection, onTap: _navigateToManageUser),
    ];

    if (canManageParticipants) {
      children.addAll([
        if (_sharees.isNotEmpty) const SizedBox(height: Spacing.sm),
        ShareMenuItem(
          title: AppLocalizations.of(context).addAdmin,
          icon: HugeIcons.strokeRoundedCrown,
          showChevron: true,
          onTap: () async {
            await routeToPage(
              context,
              AddParticipantPage(
                [_collection],
                const [ActionTypesToShow.addAdmin],
              ),
            );
            await _refreshCollection();
          },
        ),
        const SizedBox(height: Spacing.sm),
        ShareMenuItem(
          title: AppLocalizations.of(context).addCollaborator,
          icon: HugeIcons.strokeRoundedUserGroup,
          showChevron: true,
          onTap: () async {
            unawaited(
              routeToPage(
                context,
                AddParticipantPage(
                  [_collection],
                  const [ActionTypesToShow.addCollaborator],
                ),
              ).then((value) {
                _refreshCollection().ignore();
              }),
            );
          },
        ),
        const SizedBox(height: Spacing.sm),
        ShareMenuItem(
          title: AppLocalizations.of(context).addViewer,
          icon: HugeIcons.strokeRoundedView,
          showChevron: true,
          onTap: () async {
            await routeToPage(
              context,
              AddParticipantPage(
                [_collection],
                const [ActionTypesToShow.addViewer],
              ),
            );
            await _refreshCollection();
          },
        ),
        if (_sharees.isEmpty && !hasUrl)
          ShareSectionDescription(
            AppLocalizations.of(context).sharedAlbumSectionDescription,
          ),
      ]);
    }

    if (isOwner) {
      children.addAll([
        const SizedBox(height: Spacing.xxl),
        ShareSectionTitle(
          hasUrl
              ? AppLocalizations.of(context).publicLinkEnabled
              : AppLocalizations.of(context).shareALink,
        ),
      ]);
      if (hasUrl) {
        children.add(
          PublicLinkEnabledActionsWidget(
            collection: _collection,
            sendLinkButtonKey: sendLinkButtonKey,
            additionalItems: [
              ShareMenuItem(
                title: AppLocalizations.of(context).manageLink,
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
        );
      } else {
        children.addAll([
          ShareMenuItem(
            title: AppLocalizations.of(context).createPublicLink,
            subtitle: AppLocalizations.of(context).shareWithNonenteUsers,
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
          ShareSectionTitle(AppLocalizations.of(context).collectPhotos),
          ShareMenuItem(
            title: AppLocalizations.of(context).createCollaborativeLink,
            subtitle: AppLocalizations.of(context).collabLinkSectionDescription,
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

    return ShareScaffold(title: _collection.displayName, children: children);
  }
}

class EmailItemWidget extends StatelessWidget {
  final Collection collection;
  final Function? onTap;

  const EmailItemWidget(this.collection, {this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    if (collection.getSharees().isEmpty) {
      return const SizedBox.shrink();
    } else if (collection.getSharees().length == 1) {
      final User? user = collection.getSharees().firstOrNull;
      final resolvedName = user == null ? '' : resolveDisplayName(user);
      return ShareMenuItem(
        title: resolvedName,
        leading: UserAvatarWidget(
          collection.getSharees().first,
          thumbnailView: false,
        ),
        showChevron: true,
        onTap: () async {
          if (onTap != null) {
            onTap!();
          }
        },
      );
    } else {
      final sharees = collection.getSharees();
      const avatarSize = 24.0;
      final total = sharees.length;
      final limit = total > 2 ? 1 : 2;

      return ShareMenuItem(
        title: AppLocalizations.of(context).manageParticipants,
        subtitle: AppLocalizations.of(
          context,
        ).albumParticipantsCount(count: sharees.length + 1),
        leading: SizedBox(
          height: avatarSize,
          child: AlbumSharesIcons(
            sharees: sharees,
            padding: EdgeInsets.zero,
            limitCountTo: limit,
            type: AvatarType.medium,
            removeBorder: false,
          ),
        ),
        showChevron: true,
        onTap: () async {
          if (onTap != null) {
            onTap!();
          }
        },
      );
    }
  }
}
