import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/force_reload_home_gallery_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/settings/gallery_settings_screen.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";

class GalleryLayoutSettings extends StatefulWidget {
  const GalleryLayoutSettings({super.key});

  @override
  State<GalleryLayoutSettings> createState() => _GalleryLayoutSettingsState();
}

class _GalleryLayoutSettingsState extends State<GalleryLayoutSettings> {
  bool isDayLayout =
      localSettings.getGalleryGroupType() == GroupType.day &&
      localSettings.getPhotoGridSize() == 3;
  bool isMonthLayout =
      localSettings.getGalleryGroupType() == GroupType.month &&
      localSettings.getPhotoGridSize() == 5;

  void _reloadWithLatestSetting() {
    if (!mounted) return;
    setState(() {
      isDayLayout =
          localSettings.getGalleryGroupType() == GroupType.day &&
          localSettings.getPhotoGridSize() == 3;
      isMonthLayout =
          localSettings.getGalleryGroupType() == GroupType.month &&
          localSettings.getPhotoGridSize() == 5;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return BottomSheetComponent(
      title: context.l10n.layout,
      content: MenuGroupComponent(
        items: [
          MenuComponent(
            title: context.l10n.day,
            leading: const Icon(Icons.grid_view_outlined),
            trailing: isDayLayout
                ? Icon(Icons.check, color: colors.primary)
                : null,
            showOnlyLoadingState: true,
            onTap: () => _applyLayout(GroupType.day, 3),
          ),
          MenuComponent(
            title: context.l10n.month.capitalizeFirst(),
            leading: const Icon(Icons.grid_on_rounded),
            trailing: isMonthLayout
                ? Icon(Icons.check, color: colors.primary)
                : null,
            showOnlyLoadingState: true,
            onTap: () => _applyLayout(GroupType.month, 5),
          ),
          MenuComponent(
            title: AppLocalizations.of(context).custom,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isDayLayout && !isMonthLayout) ...[
                  Icon(Icons.check, color: colors.primary),
                  const SizedBox(width: 8),
                ],
                const Icon(Icons.chevron_right_outlined),
              ],
            ),
            onTap: () =>
                routeToPage(
                  context,
                  const GallerySettingsScreen(
                    fromGalleryLayoutSettingsCTA: true,
                  ),
                ).then((_) {
                  _reloadWithLatestSetting();
                }),
          ),
        ],
      ),
    );
  }

  Future<void> _applyLayout(GroupType groupType, int gridSize) async {
    await Future.wait([
      localSettings.setGalleryGroupType(groupType),
      localSettings.setPhotoGridSize(gridSize),
    ]);
    Bus.instance.fire(ForceReloadHomeGalleryEvent("Gallery layout changed"));

    if (!mounted) return;
    Navigator.pop(context);
  }
}
