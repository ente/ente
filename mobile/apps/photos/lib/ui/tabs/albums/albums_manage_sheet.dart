import "dart:async";

import "package:collection/collection.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_lock_screen/local_authentication_service.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/hidden_service.dart";
import "package:photos/ui/tabs/shared/all_links_page.dart";
import "package:photos/ui/viewer/gallery/archive_page.dart";
import "package:photos/ui/viewer/gallery/hidden_page.dart";
import "package:photos/ui/viewer/gallery/trash_page.dart";
import "package:photos/ui/viewer/gallery/uncategorized_page.dart";

Future<void> showAlbumsManageSheet(BuildContext context) {
  final strings = AppLocalizations.of(context);
  return showBottomSheetComponent<void>(
    context: context,
    builder: (sheetContext) {
      final colors = sheetContext.componentColors;
      return BottomSheetComponent(
        title: strings.more,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _manageItem(
              label: strings.links,
              icon: HugeIcons.strokeRoundedLink02,
              iconColor: colors.blue,
              onTap: () async {
                final data = await CollectionsService.instance
                    .getSharedCollectionsAndMemoryLinks();
                if (!context.mounted) return;
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
                unawaited(
                  routeToPage(
                    context,
                    AllLinksPage(
                      quickLinks: data.collections.quickLinks,
                      memoryShares: data.memoryLinks,
                      titleHeroTag: "manage_links",
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _manageItem(
              label: strings.uncategorized,
              icon: HugeIcons.strokeRoundedHelpCircle,
              iconColor: colors.textLight,
              onTap: () async {
                Collection? collection = CollectionsService.instance
                    .getActiveCollections()
                    .firstWhereOrNull(
                      (c) =>
                          c.type == CollectionType.uncategorized &&
                          c.isOwner(Configuration.instance.getUserID()!),
                    );
                collection ??= await CollectionsService.instance
                    .getUncategorizedCollection();
                if (!context.mounted) return;
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
                unawaited(routeToPage(context, UnCategorizedPage(collection)));
              },
            ),
            const SizedBox(height: 8),
            _manageItem(
              label: strings.archiveCollectionName,
              icon: HugeIcons.strokeRoundedArchive03,
              iconColor: colors.primary,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                unawaited(routeToPage(context, const ArchivePage()));
              },
            ),
            const SizedBox(height: 8),
            _manageItem(
              label: strings.hidden,
              icon: HugeIcons.strokeRoundedViewOffSlash,
              iconColor: colors.accentOrange,
              onTap: () async {
                final ok = await LocalAuthenticationService.instance
                    .requestLocalAuthentication(
                      context,
                      strings.authToViewYourHiddenFiles,
                    );
                if (!ok || !context.mounted) return;
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
                unawaited(routeToPage(context, const HiddenPage()));
              },
            ),
            const SizedBox(height: 8),
            _manageItem(
              label: strings.trash,
              icon: HugeIcons.strokeRoundedDelete01,
              iconColor: const Color(0xFFE3505A),
              onTap: () async {
                final ok = await LocalAuthenticationService.instance
                    .requestLocalAuthentication(
                      context,
                      strings.authToViewTrashedFiles,
                    );
                if (!ok || !context.mounted) return;
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
                unawaited(routeToPage(context, TrashPage()));
              },
            ),
          ],
        ),
      );
    },
  );
}

Widget _manageItem({
  required String label,
  required List<List<dynamic>> icon,
  required Color iconColor,
  required Future<void> Function() onTap,
}) {
  return MenuComponent(
    title: label,
    leading: HugeIcon(icon: icon, size: 18, color: iconColor),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
