import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/gallery_layout_changed_event.dart";
import "package:photos/events/hide_shared_items_from_home_gallery_event.dart";
import "package:photos/models/gallery/gallery_layout_config.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
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
  late GalleryLayoutType _layoutType;
  late int _photoGridSize;
  late GroupType _groupType;

  @override
  void initState() {
    super.initState();
    _layoutType = resolveGalleryLayoutType(
      localSettings.getGalleryLayoutType(),
    );
    _photoGridSize = localSettings.getPhotoGridSize();
    _groupType = localSettings.getGalleryGroupType();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;

    return SettingsPageScaffold(
      title: l10n.gallery,
      children: [
        if (isJustifiedLayoutAvailable) ...[
          SettingsItem(
            title: l10n.layout,
            trailing: _trailingLabel(
              context,
              _layoutTypeLabel(context, _layoutType),
            ),
            onTap: () async => _showLayoutTypeSheet(context),
          ),
          const SizedBox(height: 8),
        ],
        SettingsItem(
          title: l10n.photoGridSize,
          trailing: _trailingLabel(context, _photoGridSize.toString()),
          onTap: () async => _showPhotoGridSizeSheet(context),
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.groupBy,
          trailing: _trailingLabel(
            context,
            _groupType.getLocalizedName(context),
          ),
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

  String _layoutTypeLabel(BuildContext context, GalleryLayoutType layoutType) {
    return switch (layoutType) {
      GalleryLayoutType.grid => context.strings.grid,
      GalleryLayoutType.justified => context.strings.layoutJustified,
    };
  }

  Future<void> _showLayoutTypeSheet(BuildContext context) async {
    if (!isJustifiedLayoutAvailable) return;
    final l10n = context.strings;
    await showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.layout,
        content: MenuGroupComponent(
          items: [
            for (final layoutType in GalleryLayoutType.values)
              MenuComponent(
                key: ValueKey(layoutType),
                title: _layoutTypeLabel(sheetContext, layoutType),
                trailing: _layoutType == layoutType
                    ? Icon(
                        Icons.check,
                        color: sheetContext.componentColors.primary,
                      )
                    : null,
                onTap: () async {
                  await _setLayoutType(layoutType);
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

  Future<void> _setLayoutType(GalleryLayoutType layoutType) async {
    if (layoutType == GalleryLayoutType.justified &&
        !isJustifiedLayoutAvailable) {
      return;
    }
    if (localSettings.getGalleryLayoutType() == layoutType) return;
    await localSettings.setGalleryLayoutType(layoutType);
    if (mounted) {
      setState(() {
        _layoutType = layoutType;
      });
    }
    Bus.instance.fire(GalleryLayoutChangedEvent());
  }

  Future<void> _showPhotoGridSizeSheet(BuildContext context) async {
    final l10n = context.strings;
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
    if (localSettings.getPhotoGridSize() == gridSize) return;
    await localSettings.setPhotoGridSize(gridSize);
    if (mounted) {
      setState(() {
        _photoGridSize = gridSize;
      });
    }
    Bus.instance.fire(GalleryLayoutChangedEvent());
  }

  Future<void> _showGroupTypeSheet(BuildContext context) async {
    final l10n = context.strings;
    await showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.groupBy,
        content: MenuGroupComponent(
          items: [
            for (final groupType in _groupTypes)
              MenuComponent(
                key: ValueKey(groupType),
                title: groupType.getLocalizedName(sheetContext),
                trailing: _groupType == groupType
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
    if (localSettings.getGalleryGroupType() == groupType) return;
    await localSettings.setGalleryGroupType(groupType);
    if (mounted) {
      setState(() {
        _groupType = groupType;
      });
    }
    Bus.instance.fire(GalleryLayoutChangedEvent());
  }
}
