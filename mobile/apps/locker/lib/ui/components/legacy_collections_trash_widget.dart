import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/services/trash/trash_service.dart";
import "package:locker/ui/pages/all_collections_page.dart";
import "package:locker/ui/pages/trash_page.dart";
import "package:locker/ui/settings/components/settings_item.dart";
import "package:locker/ui/utils/legacy_utils.dart";

class LegacyCollectionsTrashWidget extends StatelessWidget {
  const LegacyCollectionsTrashWidget({super.key});

  @override
  Widget build(BuildContext context) {
    const sectionSpacing = SizedBox(height: 8);

    return const Column(
      children: [
        _LegacyItem(),
        sectionSpacing,
        Row(
          children: [
            Expanded(child: _CollectionsItem()),
            SizedBox(width: 8),
            Expanded(child: _TrashItem()),
          ],
        ),
      ],
    );
  }
}

class _CollectionsItem extends StatelessWidget {
  const _CollectionsItem();

  @override
  Widget build(BuildContext context) {
    return SettingsItem(
      title: context.l10n.collections,
      icon: HugeIcons.strokeRoundedWallet05,
      showChevron: false,
      titleMaxLines: 1,
      onTap: () => _openCollections(context),
    );
  }

  Future<void> _openCollections(BuildContext context) async {
    await routeToPage(context, const AllCollectionsPage());
  }
}

class _TrashItem extends StatelessWidget {
  const _TrashItem();

  @override
  Widget build(BuildContext context) {
    return SettingsItem(
      title: context.l10n.trash,
      icon: HugeIcons.strokeRoundedDelete02,
      showChevron: false,
      showOnlyLoadingState: true,
      titleMaxLines: 1,
      onTap: () => _openTrash(context),
    );
  }

  Future<void> _openTrash(BuildContext context) async {
    final trashFiles = await TrashService.instance.getTrashFiles();
    if (!context.mounted) return;
    await routeToPage(context, TrashPage(trashFiles: trashFiles));
  }
}

class _LegacyItem extends StatelessWidget {
  const _LegacyItem();

  @override
  Widget build(BuildContext context) {
    return SettingsItem(
      title: context.l10n.legacy,
      icon: HugeIcons.strokeRoundedFavourite,
      onTap: () => openLegacyPage(context),
    );
  }
}
