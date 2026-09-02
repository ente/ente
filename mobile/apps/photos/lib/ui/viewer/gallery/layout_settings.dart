import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/gallery_layout_changed_event.dart";
import "package:photos/models/gallery/gallery_layout_config.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/settings/gallery_settings_screen.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";

class GalleryLayoutSettings extends StatefulWidget {
  const GalleryLayoutSettings({super.key});

  @override
  State<GalleryLayoutSettings> createState() => _GalleryLayoutSettingsState();
}

class _GalleryLayoutSettingsState extends State<GalleryLayoutSettings> {
  late bool isDayLayout;
  late bool isMonthLayout;
  late bool isJustifiedLayout;

  @override
  void initState() {
    super.initState();
    _readLatestSetting();
  }

  void _readLatestSetting() {
    final layoutType = resolveGalleryLayoutType(
      localSettings.getGalleryLayoutType(),
    );
    isDayLayout =
        layoutType == GalleryLayoutType.grid &&
        localSettings.getGalleryGroupType() == GroupType.day &&
        localSettings.getPhotoGridSize() == 3;
    isMonthLayout =
        layoutType == GalleryLayoutType.grid &&
        localSettings.getGalleryGroupType() == GroupType.month &&
        localSettings.getPhotoGridSize() == 5;
    isJustifiedLayout = layoutType == GalleryLayoutType.justified;
  }

  void _reloadWithLatestSetting() {
    if (!mounted) return;
    setState(() {
      _readLatestSetting();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return BottomSheetComponent(
      title: context.strings.layout,
      content: MenuGroupComponent(
        items: [
          MenuComponent(
            title: context.strings.day,
            leading: const Icon(Icons.grid_view_outlined),
            trailing: isDayLayout
                ? Icon(Icons.check, color: colors.primary)
                : null,
            showOnlyLoadingState: true,
            onTap: () => _applyLayout(GroupType.day, 3),
          ),
          MenuComponent(
            title: context.strings.month.capitalizeFirst(),
            leading: const Icon(Icons.grid_on_rounded),
            trailing: isMonthLayout
                ? Icon(Icons.check, color: colors.primary)
                : null,
            showOnlyLoadingState: true,
            onTap: () => _applyLayout(GroupType.month, 5),
          ),
          if (isJustifiedLayoutAvailable)
            MenuComponent(
              title: context.strings.layoutJustified,
              leading: const Icon(Icons.view_quilt_outlined),
              trailing: isJustifiedLayout
                  ? Icon(Icons.check, color: colors.primary)
                  : null,
              showOnlyLoadingState: true,
              onTap: _applyJustifiedLayout,
            ),
          MenuComponent(
            title: context.strings.custom,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isDayLayout && !isMonthLayout && !isJustifiedLayout) ...[
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
    final alreadyApplied =
        localSettings.getGalleryLayoutType() == GalleryLayoutType.grid &&
        localSettings.getGalleryGroupType() == groupType &&
        localSettings.getPhotoGridSize() == gridSize;
    if (!alreadyApplied) {
      await Future.wait([
        localSettings.setGalleryLayoutType(GalleryLayoutType.grid),
        localSettings.setGalleryGroupType(groupType),
        localSettings.setPhotoGridSize(gridSize),
      ]);
      Bus.instance.fire(GalleryLayoutChangedEvent());
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _applyJustifiedLayout() async {
    if (!isJustifiedLayoutAvailable) return;
    if (localSettings.getGalleryLayoutType() != GalleryLayoutType.justified) {
      await localSettings.setGalleryLayoutType(GalleryLayoutType.justified);
      Bus.instance.fire(GalleryLayoutChangedEvent());
    }

    if (!mounted) return;
    Navigator.pop(context);
  }
}
