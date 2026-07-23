import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/force_reload_home_gallery_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/captioned_text_widget.dart";
import "package:photos/ui/components/divider_widget.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget.dart";
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
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Align(
                    child: Text(
                      context.l10n.layout,
                      style: textTheme.largeBold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Column(
                  children: [
                    MenuItemWidget(
                      leadingIcon: Icons.grid_view_outlined,
                      captionedTextWidget: CaptionedTextWidget(
                        title: context.l10n.day,
                      ),
                      menuItemColor: colorScheme.fillFaint,
                      alignCaptionedTextToLeft: true,
                      isBottomBorderRadiusRemoved: true,
                      showOnlyLoadingState: true,
                      trailingIcon: isDayLayout ? Icons.check : null,
                      onTap: () async {
                        final futures = <Future>[
                          localSettings.setGalleryGroupType(GroupType.day),
                          localSettings.setPhotoGridSize(3),
                        ];

                        await Future.wait(futures);
                        Bus.instance.fire(
                          ForceReloadHomeGalleryEvent("Gallery layout changed"),
                        );

                        if (!context.mounted) return;
                        Navigator.pop(context);
                      },
                    ),
                    DividerWidget(
                      dividerType: DividerType.menuNoIcon,
                      bgColor: getEnteColorScheme(context).fillFaint,
                    ),
                    MenuItemWidget(
                      leadingIcon: Icons.grid_on_rounded,
                      captionedTextWidget: CaptionedTextWidget(
                        title: context.l10n.month,
                      ),
                      menuItemColor: colorScheme.fillFaint,
                      alignCaptionedTextToLeft: true,
                      isTopBorderRadiusRemoved: true,
                      isBottomBorderRadiusRemoved: true,
                      showOnlyLoadingState: true,
                      trailingIcon: isMonthLayout ? Icons.check : null,
                      onTap: () async {
                        final futures = <Future>[
                          localSettings.setGalleryGroupType(GroupType.month),
                          localSettings.setPhotoGridSize(5),
                        ];

                        await Future.wait(futures);
                        Bus.instance.fire(
                          ForceReloadHomeGalleryEvent("Gallery layout changed"),
                        );

                        if (!context.mounted) return;
                        Navigator.pop(context);
                      },
                    ),
                    DividerWidget(
                      dividerType: DividerType.menuNoIcon,
                      bgColor: getEnteColorScheme(context).fillFaint,
                    ),
                    MenuItemWidget(
                      captionedTextWidget: CaptionedTextWidget(
                        title: AppLocalizations.of(context).custom,
                      ),
                      menuItemColor: colorScheme.fillFaint,
                      alignCaptionedTextToLeft: true,
                      showOnlyLoadingState: true,
                      isTopBorderRadiusRemoved: true,
                      leadingIcon: isDayLayout || isMonthLayout
                          ? null
                          : Icons.check,
                      trailingWidget: Icon(
                        Icons.chevron_right_outlined,
                        color: colorScheme.strokeBase,
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
                const SizedBox(height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
