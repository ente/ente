import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/services/collections/models/collection_view_type.dart";
import "package:locker/services/configuration.dart";
import "package:locker/utils/collection_actions.dart";

class CollectionPopupMenuWidget extends StatelessWidget {
  final Collection collection;
  final Widget? child;

  const CollectionPopupMenuWidget({
    super.key,
    required this.collection,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return EntePopupMenuButton<String>(
      optionsBuilder: () => _buildOptions(context),
      onSelected: (value) => _handleMenuAction(context, value),
      child: child,
    );
  }

  List<EntePopupMenuOption<String>> _buildOptions(BuildContext context) {
    final colors = context.componentColors;

    final collectionViewType = getCollectionViewType(
      collection,
      Configuration.instance.getUserID()!,
    );

    final options = <EntePopupMenuOption<String>>[];

    if (collectionViewType == CollectionViewType.ownedCollection ||
        collectionViewType == CollectionViewType.hiddenOwnedCollection ||
        collectionViewType == CollectionViewType.quickLink) {
      options.add(
        EntePopupMenuOption(
          value: 'edit',
          label: context.l10n.edit,
          leadingWidget: HugeIcon(
            icon: HugeIcons.strokeRoundedEdit02,
            color: colors.textBase,
            size: IconSizes.small,
          ),
        ),
      );
      options.add(
        EntePopupMenuOption(
          value: 'delete',
          label: context.l10n.delete,
          labelColor: colors.warning,
          leadingWidget: HugeIcon(
            icon: HugeIcons.strokeRoundedDelete01,
            color: colors.warning,
            size: IconSizes.small,
          ),
        ),
      );
    }

    if (collectionViewType == CollectionViewType.sharedCollectionViewer ||
        collectionViewType == CollectionViewType.sharedCollectionCollaborator) {
      options.add(
        EntePopupMenuOption(
          value: 'leave_collection',
          label: context.l10n.leaveCollection,
          labelColor: colors.warning,
          leadingWidget: HugeIcon(
            icon: HugeIcons.strokeRoundedLogout02,
            color: colors.warning,
            size: IconSizes.small,
          ),
        ),
      );
    }

    return options;
  }

  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'edit':
        _editCollection(context);
        break;
      case 'delete':
        _deleteCollection(context);
        break;
      case 'leave_collection':
        _leaveCollection(context);
        break;
    }
  }

  Future<void> _editCollection(BuildContext context) async {
    await CollectionActions.editCollection(context, collection);
  }

  Future<void> _deleteCollection(BuildContext context) async {
    await CollectionActions.deleteCollection(context, collection);
  }

  Future<void> _leaveCollection(BuildContext context) async {
    await CollectionActions.leaveCollection(context, collection);
  }
}
