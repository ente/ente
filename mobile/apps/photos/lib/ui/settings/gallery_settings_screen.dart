import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/gallery_layout_changed_event.dart";
import "package:photos/events/hide_shared_items_from_home_gallery_event.dart";
import "package:photos/models/gallery/gallery_layout_config.dart";
import "package:photos/models/gallery/justified_layout_strategy.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/settings/justified_layout_tuning_screen.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:photos/ui/viewer/gallery/justified_layout_strategy_label.dart";

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
  late JustifiedLayoutStrategy _justifiedStrategy;
  late int _photoGridSize;
  late GroupType _groupType;

  @override
  void initState() {
    super.initState();
    _layoutType = resolveGalleryLayoutType(
      localSettings.getGalleryLayoutType(),
    );
    _photoGridSize = localSettings.getPhotoGridSize();
    _justifiedStrategy = localSettings.getJustifiedLayoutStrategy();
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
            title: "${l10n.layout} (i)",
            trailing: _trailingLabel(
              context,
              _layoutTypeLabel(context, _layoutType, _justifiedStrategy),
            ),
            onTap: () async => _showLayoutTypeSheet(context),
          ),
          const SizedBox(height: 8),
          SettingsItem(
            title: "Justified layout tuning (i)",
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const JustifiedLayoutTuningScreen(),
                ),
              );
            },
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

  String _layoutTypeLabel(
    BuildContext context,
    GalleryLayoutType layoutType,
    JustifiedLayoutStrategy? strategy,
  ) {
    return switch (layoutType) {
      GalleryLayoutType.grid => context.strings.grid,
      GalleryLayoutType.justified => strategy!.label(context),
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
            for (final (layoutType, strategy) in [
              (GalleryLayoutType.grid, null),
              for (final strategy in JustifiedLayoutStrategy.values)
                (GalleryLayoutType.justified, strategy),
            ])
              MenuComponent(
                key: ValueKey((layoutType, strategy)),
                title: _layoutTypeLabel(sheetContext, layoutType, strategy),
                trailing:
                    _layoutType == layoutType &&
                        (strategy == null || _justifiedStrategy == strategy)
                    ? Icon(
                        Icons.check,
                        color: sheetContext.componentColors.primary,
                      )
                    : null,
                onTap: () async {
                  await _setLayoutType(layoutType, strategy);
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

  Future<void> _setLayoutType(
    GalleryLayoutType layoutType,
    JustifiedLayoutStrategy? strategy,
  ) async {
    if (layoutType == GalleryLayoutType.justified &&
        !isJustifiedLayoutAvailable) {
      return;
    }
    if (localSettings.getGalleryLayoutType() == layoutType &&
        (strategy == null ||
            localSettings.getJustifiedLayoutStrategy() == strategy)) {
      return;
    }
    await Future.wait([
      localSettings.setGalleryLayoutType(layoutType),
      if (strategy != null) localSettings.setJustifiedLayoutStrategy(strategy),
    ]);
    if (mounted) {
      setState(() {
        _layoutType = layoutType;
        if (strategy != null) _justifiedStrategy = strategy;
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
