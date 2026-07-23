import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/force_reload_home_gallery_event.dart";
import "package:photos/events/hide_shared_items_from_home_gallery_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/settings/components/settings_item.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";

class GallerySettingsScreen extends StatefulWidget {
  final bool fromGalleryLayoutSettingsCTA;
  const GallerySettingsScreen({
    super.key,
    required this.fromGalleryLayoutSettingsCTA,
  });

  @override
  State<GallerySettingsScreen> createState() => _GallerySettingsScreenState();
}

class _GallerySettingsScreenState extends State<GallerySettingsScreen> {
  late int _photoGridSize;
  late String _groupType;

  @override
  void initState() {
    super.initState();
    _photoGridSize = localSettings.getPhotoGridSize();
    _groupType = localSettings.getGalleryGroupType().name;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SettingsPageScaffold(
      title: l10n.gallery,
      children: [
        SettingsItem(
          title: l10n.photoGridSize,
          trailing: _trailingLabel(context, _photoGridSize.toString()),
          onTap: () async => _showPhotoGridSizeSheet(context),
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.groupBy,
          trailing: _trailingLabel(context, _groupType),
          onTap: () async => _showGroupTypeSheet(context),
        ),
        if (!widget.fromGalleryLayoutSettingsCTA && !isLocalGalleryMode) ...[
          const SizedBox(height: 8),
          SettingsItem(
            title: l10n.hideSharedItemsFromHomeGallery,
            showChevron: false,
            trailing: ToggleSwitchComponent.async(
              value: () => localSettings.hideSharedItemsFromHomeGallery,
              onChanged: () async {
                final prevSetting =
                    localSettings.hideSharedItemsFromHomeGallery;
                await localSettings.setHideSharedItemsFromHomeGallery(
                  !prevSetting,
                );

                Bus.instance.fire(
                  HideSharedItemsFromHomeGalleryEvent(!prevSetting),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _trailingLabel(BuildContext context, String label) {
    final colors = context.componentColors;
    return Text(
      label,
      style: TextStyles.mini.copyWith(color: colors.textLight),
    );
  }

  Future<void> _showPhotoGridSizeSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    await showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.photoGridSize,
        content: MenuGroupComponent(
          items: [
            for (
              int gridSize = photoGridSizeMin;
              gridSize <= photoGridSizeMax;
              gridSize++
            )
              MenuComponent(
                key: ValueKey(gridSize),
                title: "$gridSize",
                trailing: _photoGridSize == gridSize
                    ? Icon(
                        Icons.check,
                        color: sheetContext.componentColors.primary,
                      )
                    : null,
                onTap: () async {
                  await _setPhotoGridSize(gridSize);
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setPhotoGridSize(int gridSize) async {
    await localSettings.setPhotoGridSize(gridSize);
    if (mounted) {
      setState(() {
        _photoGridSize = gridSize;
      });
    }
    Bus.instance.fire(ForceReloadHomeGalleryEvent("grid size changed"));
  }

  Future<void> _showGroupTypeSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final currentGroupType = localSettings.getGalleryGroupType();
    await showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.groupBy,
        content: MenuGroupComponent(
          items: [
            for (final groupType in _groupTypes)
              MenuComponent(
                key: ValueKey(groupType.name),
                title: groupType.getLocalizedName(sheetContext),
                trailing: currentGroupType == groupType
                    ? Icon(
                        Icons.check,
                        color: sheetContext.componentColors.primary,
                      )
                    : null,
                onTap: () async {
                  await _setGroupType(groupType);
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  List<GroupType> get _groupTypes {
    return GroupType.values
        .where((type) => type != GroupType.size && type != GroupType.none)
        .toList();
  }

  Future<void> _setGroupType(GroupType groupType) async {
    await localSettings.setGalleryGroupType(groupType);
    if (mounted) {
      setState(() {
        _groupType = groupType.name;
      });
    }
    Bus.instance.fire(ForceReloadHomeGalleryEvent("group type changed"));
  }
}
