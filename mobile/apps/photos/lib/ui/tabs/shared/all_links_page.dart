import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/memory_share/memory_share.dart";
import "package:photos/models/button_result.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/collection/collection_items.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/memory_share_service.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/components/alert_bottom_sheet.dart";
import "package:photos/ui/components/buttons/button_widget.dart"
    show ButtonAction;
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import "package:photos/ui/components/empty_state_component.dart";
import "package:photos/ui/sharing/memory_link_details_sheet.dart";
import "package:photos/ui/tabs/shared/memory_link_item.dart";
import "package:photos/ui/tabs/shared/quick_link_album_item.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";
import "package:photos/utils/dialog_util.dart";

class AllLinksPage extends StatefulWidget {
  final List<Collection> quickLinks;
  final List<MemoryShare> memoryShares;
  final String titleHeroTag;

  const AllLinksPage({
    required this.quickLinks,
    required this.memoryShares,
    required this.titleHeroTag,
    super.key,
  });

  @override
  State<AllLinksPage> createState() => _AllLinksPageState();
}

class _AllLinksPageState extends State<AllLinksPage> {
  static const _quickLinkHeroTagPrefix = "outgoing_collection";

  final List<Collection> _selectedQuickLinks = [];
  final Set<int> _selectedMemoryShareIDs = {};

  bool get _hasSelection =>
      _selectedQuickLinks.isNotEmpty || _selectedMemoryShareIDs.isNotEmpty;

  Future<void> _navigateToCollectionPage(Collection c) async {
    final thumbnail = await CollectionsService.instance.getCover(c);
    if (!mounted) return;
    unawaited(
      routeToPage(
        context,
        CollectionPage(
          CollectionWithThumbnail(c, thumbnail),
          tagPrefix: _quickLinkHeroTagPrefix,
        ),
      ),
    );
  }

  Future<void> _toggleQuickLinkSelection(Collection c) async {
    if (_selectedQuickLinks.contains(c)) {
      _selectedQuickLinks.remove(c);
    } else {
      if (!_hasSelection) {
        await HapticFeedback.mediumImpact();
      }
      _selectedQuickLinks.add(c);
    }
    setState(() {});
  }

  Future<void> _toggleMemoryShareSelection(MemoryShare share) async {
    if (_selectedMemoryShareIDs.contains(share.id)) {
      _selectedMemoryShareIDs.remove(share.id);
    } else {
      if (!_hasSelection) {
        await HapticFeedback.mediumImpact();
      }
      _selectedMemoryShareIDs.add(share.id);
    }
    setState(() {});
  }

  Future<void> _removeSelectedLinks() async {
    if (!_hasSelection) {
      await showErrorDialog(
        context,
        AppLocalizations.of(context).deleteLinkQuestion,
        AppLocalizations.of(context).pleaseSelectQuickLinksToRemove,
      );
      return;
    }
    final result = await showAlertBottomSheet<ButtonResult>(
      context,
      title: AppLocalizations.of(context).removePublicLinks,
      message: AppLocalizations.of(context).deleteMemoryLinkMessage,
      assetPath: "assets/warning-grey.png",
      buttons: [
        ButtonWidgetV2(
          buttonType: ButtonTypeV2.critical,
          labelText: AppLocalizations.of(context).remove,
          isInAlert: true,
          buttonAction: ButtonAction.first,
          onTap: _deleteSelectedLinks,
        ),
      ],
    );
    if (result?.action == ButtonAction.error && context.mounted) {
      if (!mounted) return;
      await showGenericErrorBottomSheet(
        context: context,
        error: result?.exception,
      );
    }
  }

  Future<void> _deleteSelectedLinks() async {
    for (final link in List<Collection>.of(_selectedQuickLinks)) {
      await CollectionActions(
        CollectionsService.instance,
      ).trashCollectionKeepingPhotos(link);
      if (!mounted) return;
      setState(() {
        widget.quickLinks.remove(link);
        _selectedQuickLinks.remove(link);
      });
    }
    for (final shareID in Set<int>.of(_selectedMemoryShareIDs)) {
      await MemoryShareService.instance.deleteMemoryShare(shareID);
      if (!mounted) return;
      setState(() {
        widget.memoryShares.removeWhere((share) => share.id == shareID);
        _selectedMemoryShareIDs.remove(shareID);
      });
    }
  }

  Future<void> _openMemoryLink(MemoryShare share) async {
    final deleted = await showMemoryLinkDetailsSheet(
      context,
      shareUrl: share.url,
      shareId: share.id,
    );
    if (deleted != true || !mounted) return;
    setState(() {
      widget.memoryShares.removeWhere((m) => m.id == share.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final linkItems = <Object>[...widget.quickLinks, ...widget.memoryShares];
    final hasLinks = linkItems.isNotEmpty;
    final linksCount = widget.quickLinks.length + widget.memoryShares.length;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: AppBarComponent(
        title: AppLocalizations.of(context).links,
        subtitle: AppLocalizations.of(context).itemCount(count: linksCount),
        physics: const BouncingScrollPhysics(),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _hasSelection
                ? IconButtonComponent(
                    key: const ValueKey("delete_links"),
                    variant: IconButtonComponentVariant.primary,
                    shouldSurfaceExecutionStates: false,
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedDelete01,
                      color: colors.warning,
                    ),
                    onTap: _removeSelectedLinks,
                  )
                : const SizedBox.shrink(key: ValueKey("no_selection_action")),
          ),
        ],
        slivers: [
          if (hasLinks) ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: linkItems.length,
                itemBuilder: (context, index) {
                  final item = linkItems[index];
                  if (item is Collection) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (_hasSelection) {
                          _toggleQuickLinkSelection(item);
                        } else {
                          _navigateToCollectionPage(item);
                        }
                      },
                      onLongPress: () {
                        if (_hasSelection) {
                          _navigateToCollectionPage(item);
                        } else {
                          _toggleQuickLinkSelection(item);
                        }
                      },
                      child: QuickLinkAlbumItem(
                        c: item,
                        selectedQuickLinks: _selectedQuickLinks,
                      ),
                    );
                  }

                  final share = item as MemoryShare;
                  final title =
                      MemoryShareService.instance.getMemoryShareTitle(share) ??
                      AppLocalizations.of(context).memoryLink;
                  return MemoryLinkAlbumItem(
                    title: title,
                    fileCount: share.fileCount,
                    previewUploadedFileID: share.previewUploadedFileID,
                    isSelected: _selectedMemoryShareIDs.contains(share.id),
                    onTap: () {
                      if (_hasSelection) {
                        _toggleMemoryShareSelection(share);
                      } else {
                        _openMemoryLink(share);
                      }
                    },
                    onLongPress: () => _toggleMemoryShareSelection(share),
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(height: 8),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
          if (!hasLinks)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateComponent(
                assetPath: "assets/empty_state_links.png",
                title: AppLocalizations.of(context).activeLinksWillShowUpHere,
              ),
            ),
        ],
      ),
    );
  }
}
