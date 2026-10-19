import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_sharing/models/user.dart";
import "package:ente_sharing/user_avator_widget.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/extensions/user_extension.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/services/configuration.dart";
import "package:locker/ui/components/custom_list_scrollbar.dart";
import "package:locker/ui/sharing/add_email_bottom_sheet.dart";
import "package:locker/ui/sharing/manage_links_widget.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";
import "package:locker/utils/collection_actions.dart";

Future<void> showShareCollectionSheet(
  BuildContext context, {
  required Collection collection,
}) {
  return showBottomSheetComponent<void>(
    context: context,
    builder: (_) => ShareCollectionSheet(collection: collection),
  );
}

class ShareCollectionSheet extends StatefulWidget {
  final Collection collection;

  const ShareCollectionSheet({super.key, required this.collection});

  @override
  State<ShareCollectionSheet> createState() => _ShareCollectionSheetState();
}

class _ShareCollectionSheetState extends State<ShareCollectionSheet> {
  late CollectionActions _collectionActions;
  final ScrollController _scrollController = ScrollController();

  List<User> get _sharees => widget.collection.getSharees();

  bool get _isOwner {
    final currentUserId = Configuration.instance.getUserID();
    return widget.collection.owner.id == currentUserId;
  }

  @override
  void initState() {
    super.initState();
    _collectionActions = CollectionActions();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final shouldShowSharedWithLabel = !_isOwner || _sharees.isNotEmpty;

    return BottomSheetComponent(
      title: context.strings.shareCollection,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isOwner) ...[_buildOwnerActions(), const SizedBox(height: 20)],
          if (shouldShowSharedWithLabel) ...[
            Text(
              context.strings.sharedWith,
              style: TextStyles.body.copyWith(color: colors.textLight),
            ),
            const SizedBox(height: 8),
          ],
          _buildShareesList(),
        ],
      ),
    );
  }

  bool get _hasPublicLink => widget.collection.publicURLs.isNotEmpty;

  Widget _buildShareesList() {
    final colors = context.componentColors;

    final List<User> allUsers = [];

    if (!_isOwner) {
      final owner = widget.collection.owner;
      owner.role = CollectionParticipantRole.owner.toStringVal();
      allUsers.add(owner);
    }

    allUsers.addAll(_sharees);

    if (allUsers.isEmpty) {
      return const SizedBox.shrink();
    }

    const double maxVisibleHeight = 244.0;
    final showScrollbar = allUsers.length > 4;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: maxVisibleHeight),
              child: ListView.separated(
                controller: _scrollController,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: allUsers.length,
                separatorBuilder: (_, _) => ColoredBox(
                  color: colors.fillLight,
                  child: const DividerComponent(
                    padding: EdgeInsets.only(left: 48),
                  ),
                ),
                itemBuilder: (context, index) {
                  final user = allUsers[index];
                  final role = CollectionParticipantRoleExtn.fromString(
                    user.role,
                  );
                  return MenuGroupComponent(
                    backgroundColor: colors.fillLight,
                    borderRadius: MenuGroupComponent.itemBorderRadius(
                      index: index,
                      itemCount: allUsers.length,
                    ),
                    items: [
                      MenuComponent(
                        title: user.email,
                        leading: UserAvatarWidget(
                          user,
                          config: Configuration.instance,
                          type: AvatarType.mini,
                        ),
                        trailing: _isOwner
                            ? _buildRolePopupMenu(user)
                            : _buildRoleIcon(role),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        if (showScrollbar) ...[
          const SizedBox(width: 4),
          CustomListScrollbar(
            scrollController: _scrollController,
            itemCount: allUsers.length,
            visibleItems: 4,
            containerHeight: maxVisibleHeight,
          ),
        ],
      ],
    );
  }

  Widget _buildOwnerActions() {
    return Row(
      children: [
        _ShareActionOption(
          icon: HugeIcons.strokeRoundedAdd01,
          label: context.strings.addEmail,
          onTap: () async {
            await showAddEmailSheet(
              context,
              collection: widget.collection,
              onShareAdded: () {
                if (mounted) {
                  setState(() {});
                }
              },
            );
          },
        ),
        if (widget.collection.type != CollectionType.uncategorized) ...[
          const SizedBox(width: 16),
          _ShareActionOption(
            icon: HugeIcons.strokeRoundedLink02,
            label: _hasPublicLink
                ? context.strings.linkSettings
                : context.strings.linkLabel,
            onTap: () async {
              if (!_hasPublicLink) {
                final result = await CollectionActions.enableUrl(
                  context,
                  widget.collection,
                );
                if (!result || !mounted) return;
              }

              await routeToPage(
                context,
                ManageSharedLinkWidget(collection: widget.collection),
              );
              if (mounted) {
                setState(() {});
              }
            },
          ),
        ],
      ],
    );
  }

  Widget _buildRoleIcon(CollectionParticipantRole role) {
    final colors = context.componentColors;
    final icon = switch (role) {
      CollectionParticipantRole.owner => HugeIcons.strokeRoundedCrown03,
      CollectionParticipantRole.collaborator =>
        HugeIcons.strokeRoundedUserMultiple,
      CollectionParticipantRole.viewer => HugeIcons.strokeRoundedView,
      _ => HugeIcons.strokeRoundedView,
    };

    return Container(
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(8),
      child: HugeIcon(icon: icon, color: colors.textLight, size: 20),
    );
  }

  Widget _buildRolePopupMenu(User user) {
    final colors = context.componentColors;
    return EntePopupMenuButton<String>(
      optionsBuilder: () => [
        EntePopupMenuOption(
          value: "remove",
          label: context.strings.removeAccess,
          labelColor: colors.warning,
          leadingWidget: HugeIcon(
            icon: HugeIcons.strokeRoundedDelete02,
            color: colors.warning,
            size: IconSizes.small,
          ),
        ),
      ],
      onSelected: (value) {
        if (value == "viewer") {
          _setUserRole(user, CollectionParticipantRole.viewer);
        } else if (value == "collaborator") {
          _setUserRole(user, CollectionParticipantRole.collaborator);
        } else if (value == "remove") {
          _removeSharee(user);
        }
      },
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedMoreVertical,
        color: colors.textBase,
      ),
    );
  }

  Future<void> _setUserRole(User user, CollectionParticipantRole role) async {
    final isDowngrade =
        user.isCollaborator && role == CollectionParticipantRole.viewer;

    if (isDowngrade) {
      final confirmed = await showBottomSheetComponent(
        context: context,
        builder: (_) => BottomSheetComponent(
          title: context.strings.changePermissions,
          message: context.strings.cannotAddMoreFilesAfterBecomingViewer(
            name: user.resolvedDisplayName,
          ),
          illustration: LockerBottomSheetIllustration.warningGrey,
          actions: [
            ButtonComponent(
              label: context.strings.yesConvertToViewer,
              variant: ButtonComponentVariant.critical,
              onTap: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }
    }

    final result = await _collectionActions.addEmailToCollection(
      mounted ? context : null,
      widget.collection,
      user.email,
      role,
      showProgress: true,
    );

    if (result && mounted) {
      user.role = role.toString();
      setState(() {});
    }
  }

  Future<void> _removeSharee(User user) async {
    final confirmed = await showBottomSheetComponent(
      context: context,
      builder: (_) => BottomSheetComponent(
        title: context.strings.removeWithQuestionMark,
        message: context.strings.removeCollectionParticipantBody(
          userEmail: user.resolvedDisplayName,
        ),
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.strings.yesRemove,
            variant: ButtonComponentVariant.critical,
            onTap: () {
              Navigator.of(context).pop(true);
            },
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final result = await _collectionActions.removeParticipant(
        context,
        widget.collection,
        user,
      );
      if (result && mounted) {
        setState(() {});
      }
    }
  }
}

class _ShareActionOption extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String label;
  final Future<void> Function() onTap;

  const _ShareActionOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await onTap();
        },
        child: Container(
          decoration: BoxDecoration(
            color: colors.fillLight,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(icon: icon, color: colors.textBase, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyles.body.copyWith(color: colors.textBase),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
