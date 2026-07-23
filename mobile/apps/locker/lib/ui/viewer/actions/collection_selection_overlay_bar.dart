import 'package:ente_components/ente_components.dart';
import "package:ente_ui/utils/toast_util.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/models/selected_collections.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/services/configuration.dart";
import "package:locker/ui/components/selection_action_button_widget.dart";
import "package:locker/ui/sharing/share_collection_bottom_sheet.dart";
import "package:locker/utils/collection_actions.dart";
import "package:locker/utils/error_sheet.dart";
import "package:logging/logging.dart";

class CollectionSelectionOverlayBar extends StatefulWidget {
  final SelectedCollections selectedCollections;
  final List<Collection> collections;

  const CollectionSelectionOverlayBar({
    required this.selectedCollections,
    required this.collections,
    super.key,
  });

  @override
  State<CollectionSelectionOverlayBar> createState() =>
      _CollectionSelectionOverlayBarState();
}

class _CollectionSelectionOverlayBarState
    extends State<CollectionSelectionOverlayBar> {
  static final _logger = Logger('CollectionSelectionOverlayBar');

  int get _currentUserID => Configuration.instance.getUserID()!;

  List<Collection> _getOwnedCollections(List<Collection> collections) {
    final ownedCollections = collections
        .where((c) => c.isOwner(_currentUserID))
        .toList();

    final sharedCount = collections.length - ownedCollections.length;
    if (sharedCount > 0 && mounted) {
      showToast(
        context,
        "Skipped $sharedCount shared collection${sharedCount > 1 ? 's' : ''} - you can only leave shared collections",
      );
    }

    return ownedCollections;
  }

  List<Collection> _getSharedIncomingCollections(List<Collection> collections) {
    return collections.where((c) => !c.isOwner(_currentUserID)).toList();
  }

  @override
  void initState() {
    super.initState();
    widget.selectedCollections.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    widget.selectedCollections.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final colors = context.componentColors;
    final hasSelection = widget.selectedCollections.collections.isNotEmpty;

    return IgnorePointer(
      ignoring: !hasSelection,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          offset: hasSelection ? Offset.zero : const Offset(0, 1),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: hasSelection ? 1.0 : 0.0,
            curve: Curves.easeInOut,
            child: hasSelection
                ? Container(
                    decoration: BoxDecoration(
                      color: colors.backgroundBase,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      border: Border(top: BorderSide(color: colors.strokeDark)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              ListenableBuilder(
                                listenable: widget.selectedCollections,
                                builder: (context, child) {
                                  final isAllSelected =
                                      widget.selectedCollections.count ==
                                      widget.collections.length;
                                  final buttonText = isAllSelected
                                      ? context.l10n.deselectAll
                                      : context.l10n.selectAll;
                                  final iconData = isAllSelected
                                      ? Icons.remove_circle_outline
                                      : Icons.check_circle_outline_outlined;

                                  return InkWell(
                                    onTap: () {
                                      if (isAllSelected) {
                                        widget.selectedCollections.clearAll();
                                      } else {
                                        widget.selectedCollections.select(
                                          widget.collections.toSet(),
                                        );
                                      }
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: colors.fillLight,
                                        borderRadius: BorderRadius.circular(50),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12.0,
                                        vertical: 10.0,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            buttonText,
                                            style: TextStyles.body,
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            iconData,
                                            color: colors.textBase,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const Spacer(),
                              ListenableBuilder(
                                listenable: widget.selectedCollections,
                                builder: (context, child) {
                                  final count =
                                      widget.selectedCollections.count;
                                  final countText = count == 1
                                      ? '1 selected'
                                      : '$count selected';

                                  return InkWell(
                                    onTap: () {
                                      widget.selectedCollections.clearAll();
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: colors.fillLight,
                                        borderRadius: BorderRadius.circular(50),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12.0,
                                        vertical: 10.0,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            countText,
                                            style: TextStyles.body,
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.close,
                                            color: colors.textBase,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildPrimaryActionButtons(),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryActionButtons() {
    final colors = context.componentColors;
    final selectedCollections = widget.selectedCollections.collections;
    if (selectedCollections.isEmpty) {
      return const SizedBox.shrink();
    }

    final isSingleSelection = selectedCollections.length == 1;
    final collection = isSingleSelection ? selectedCollections.first : null;

    final ownedCollections = selectedCollections
        .where((c) => c.isOwner(_currentUserID))
        .toList();
    final sharedIncomingCollections = _getSharedIncomingCollections(
      selectedCollections.toList(),
    );

    final hasOwnedCollections = ownedCollections.isNotEmpty;
    final hasSharedIncoming = sharedIncomingCollections.isNotEmpty;

    final primaryActions = <Widget>[
      if (isSingleSelection && hasOwnedCollections)
        SelectionActionButton(
          hugeIcon: const HugeIcon(icon: HugeIcons.strokeRoundedNavigation06),
          label: context.l10n.share,
          onTap: () => _shareCollection(collection!),
        ),
      if (isSingleSelection && hasOwnedCollections)
        SelectionActionButton(
          hugeIcon: const HugeIcon(icon: HugeIcons.strokeRoundedPencilEdit02),
          label: context.l10n.edit,
          onTap: () => _editCollection(collection!),
        ),
      if (hasSharedIncoming)
        SelectionActionButton(
          hugeIcon: HugeIcon(
            icon: HugeIcons.strokeRoundedLogout02,
            color: colors.warning,
          ),
          label: context.l10n.leaveCollection,
          onTap: () => _leaveCollections(sharedIncomingCollections),
          isDestructive: true,
        ),
      if (hasOwnedCollections)
        SelectionActionButton(
          hugeIcon: HugeIcon(
            icon: HugeIcons.strokeRoundedDelete02,
            color: colors.warning,
          ),
          label: context.l10n.delete,
          onTap: () {
            if (isSingleSelection) {
              _deleteCollection(collection!);
            } else {
              _deleteMultipleCollections(selectedCollections);
            }
          },
          isDestructive: true,
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(children: _buildActionRow(primaryActions)),
    );
  }

  List<Widget> _buildActionRow(List<Widget> actions) {
    final children = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      children.add(Expanded(child: actions[i]));
      if (i != actions.length - 1) {
        children.add(const SizedBox(width: 12));
      }
    }
    return children;
  }

  Future<void> _editCollection(Collection collection) async {
    final ownedCollections = _getOwnedCollections([collection]);
    if (ownedCollections.isEmpty) {
      widget.selectedCollections.clearAll();
      return;
    }

    try {
      await CollectionActions.editCollection(context, collection);
    } catch (e, s) {
      _logger.severe(e, s);
      if (mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
    if (mounted) {
      widget.selectedCollections.clearAll();
    }
  }

  Future<void> _deleteCollection(Collection collection) async {
    final ownedCollections = _getOwnedCollections([collection]);
    if (ownedCollections.isEmpty) {
      widget.selectedCollections.clearAll();
      return;
    }

    try {
      await CollectionActions.deleteCollection(context, collection);
    } catch (e, s) {
      _logger.severe(e, s);
      if (mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
    if (mounted) {
      widget.selectedCollections.clearAll();
    }
  }

  Future<void> _deleteMultipleCollections(Set<Collection> collections) async {
    final ownedCollections = _getOwnedCollections(collections.toList());
    if (ownedCollections.isEmpty) {
      widget.selectedCollections.clearAll();
      return;
    }

    try {
      await CollectionActions.deleteMultipleCollections(
        context,
        ownedCollections,
      );
    } catch (e, s) {
      _logger.severe(e, s);
      if (mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
    if (mounted) {
      widget.selectedCollections.clearAll();
    }
  }

  Future<void> _shareCollection(Collection collection) async {
    final ownedCollections = _getOwnedCollections([collection]);
    if (ownedCollections.isEmpty) {
      widget.selectedCollections.clearAll();
      return;
    }

    if (!collection.type.canShare) {
      showToast(context, context.l10n.collectionCannotBeShared);
      widget.selectedCollections.clearAll();
      return;
    }

    try {
      await showShareCollectionSheet(context, collection: collection);
    } catch (e, s) {
      _logger.severe(e, s);
      if (mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
    if (mounted) {
      widget.selectedCollections.clearAll();
    }
  }

  Future<void> _leaveCollections(List<Collection> collections) async {
    if (collections.isEmpty) {
      widget.selectedCollections.clearAll();
      return;
    }

    try {
      if (collections.length == 1) {
        await CollectionActions.leaveCollection(context, collections.first);
      } else {
        await CollectionActions.leaveMultipleCollection(context, collections);
      }
    } catch (e, s) {
      _logger.severe(e, s);
      if (mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
    if (mounted) {
      widget.selectedCollections.clearAll();
    }
  }
}
