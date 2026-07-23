import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_sharing/models/user.dart";
import "package:ente_sharing/user_avator_widget.dart";
import "package:ente_ui/components/captioned_text_widget_v2.dart";
import "package:ente_ui/components/divider_widget.dart";
import "package:ente_ui/components/menu_item_widget_v2.dart";
import "package:ente_utils/share_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/extensions/user_extension.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/services/collections/collections_service.dart";
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
      title: context.l10n.shareCollection,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isOwner) ...[_buildOwnerActions(), const SizedBox(height: 20)],
          if (shouldShowSharedWithLabel) ...[
            Text(
              context.l10n.sharedWith,
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
    final currentUserId = Configuration.instance.getUserID() ?? -1;

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
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: allUsers.length,
                itemBuilder: (context, index) {
                  final user = allUsers[index];
                  final isFirst = index == 0;
                  final isLast = index == allUsers.length - 1;
                  final role = CollectionParticipantRoleExtn.fromString(
                    user.role,
                  );

                  return Column(
                    children: [
                      if (!isFirst)
                        DividerWidget(
                          dividerType: DividerType.menu,
                          bgColor: colors.fillLight,
                        ),
                      MenuItemWidgetV2(
                        captionedTextWidget: CaptionedTextWidgetV2(
                          title: user.email,
                        ),
                        leadingIconSize: 24,
                        leadingIconWidget: UserAvatarWidget(
                          user,
                          currentUserID: currentUserId,
                          config: Configuration.instance,
                          type: AvatarType.mini,
                        ),
                        menuItemColor: colors.fillLight,
                        trailingWidget: _isOwner
                            ? _buildRolePopupMenu(user)
                            : _buildRoleIcon(role),
                        surfaceExecutionStates: false,
                        isTopBorderRadiusRemoved: !isFirst,
                        isBottomBorderRadiusRemoved: !isLast,
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
          label: context.l10n.addEmail,
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
        const SizedBox(width: 16),
        _ShareActionOption(
          icon: HugeIcons.strokeRoundedLink02,
          label: _hasPublicLink
              ? context.l10n.manageLink
              : context.l10n.linkLabel,
          onTap: () async {
            if (!_hasPublicLink) {
              await _createAndSharePublicLink();
              return;
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
    );
  }

  Future<void> _createAndSharePublicLink() async {
    final result = await CollectionActions.enableUrl(
      context,
      widget.collection,
    );
    if (result && mounted) {
      setState(() {});
      if (_hasPublicLink) {
        final url = CollectionService.instance.getPublicUrl(widget.collection);
        await shareText(url, context: context);
      }
    }
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
          label: context.l10n.removeAccess,
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
          title: context.l10n.changePermissions,
          message: context.l10n.cannotAddMoreFilesAfterBecomingViewer(
            user.displayName ?? user.email,
          ),
          illustration: LockerBottomSheetIllustration.warningGrey,
          actions: [
            ButtonComponent(
              label: context.l10n.yesConvertToViewer,
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
        title: context.l10n.removeWithQuestionMark,
        message: context.l10n.removeParticipantBody(
          user.displayName ?? user.email,
        ),
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.l10n.yesRemove,
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
