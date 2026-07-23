import "package:ente_components/ente_components.dart";
import "package:figma_squircle/figma_squircle.dart";
import "package:flutter/material.dart";
import "package:launcher_icon_switcher/launcher_icon_switcher.dart";
import "package:logging/logging.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";

enum AppIcon {
  iconGreen("Default", "IconGreen", "assets/launcher_icon/icon-green.png"),
  iconLight("Light", "IconLight", "assets/launcher_icon/icon-light.png"),
  iconDark("Dark", "IconDark", "assets/launcher_icon/icon-dark.png"),
  iconOG("OG", "IconOG", "assets/launcher_icon/icon-og.png"),
  iconDuckyHuggingE(
    "Ducky",
    "IconDuckyHuggingE",
    "assets/launcher_icon/icon-ducky-hugging-e.png",
  );

  final String name;
  final String id;
  final String path;
  const AppIcon(this.name, this.id, this.path);
}

class AppIconSelectionScreen extends StatefulWidget {
  const AppIconSelectionScreen({super.key});

  @override
  State<AppIconSelectionScreen> createState() => _AppIconSelectionScreenState();
}

class _AppIconSelectionScreenState extends State<AppIconSelectionScreen> {
  final _logger = Logger("_AppIconSelectionScreenState");
  final _iconSwitcher = LauncherIconSwitcher();
  String? _currentIcon;

  @override
  void initState() {
    super.initState();
    _iconSwitcher.initialize(
      AppIcon.values.map((e) => e.id).toList(),
      AppIcon.iconGreen.id,
    );
    _iconSwitcher
        .getCurrentIcon()
        .then((icon) {
          _logger.info("Current icon is " + icon);
          setState(() {
            _currentIcon = icon;
          });
        })
        .onError((error, stackTrace) {
          _logger.severe("Error getting current icon", error, stackTrace);
        });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: context.l10n.appIcon,
      children: _currentIcon == null
          ? [
              SizedBox(
                height: MediaQuery.sizeOf(context).height / 2,
                child: EnteLoadingWidget(
                  color: context.componentColors.strokeDark,
                ),
              ),
            ]
          : [
              for (final icon in AppIcon.values)
                _AppIconTile(icon, icon.id == _currentIcon, () {
                  if (icon.id != _currentIcon) {
                    _changeIcon(icon.id);
                  }
                }),
            ],
    );
  }

  Future<void> _changeIcon(String icon) async {
    try {
      _logger.info("Changing icon to " + icon);
      await _iconSwitcher.setIcon(icon);
      _logger.info("Icon changed to " + icon);
      setState(() {
        _currentIcon = icon;
      });
    } catch (error, stackTrace) {
      _logger.severe("Error changing icon", error, stackTrace);
    }
  }
}

class _AppIconTile extends StatelessWidget {
  final AppIcon appIcon;
  final bool isSelected;
  final Function() onSelect;
  const _AppIconTile(this.appIcon, this.isSelected, this.onSelect);

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () {
          onSelect();
        },
        child: Container(
          decoration: BoxDecoration(
            color: colors.fillLight,
            borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              RadioGroup<bool>(
                groupValue: true,
                onChanged: (_) {
                  onSelect();
                },
                child: Radio<bool>(
                  value: isSelected,
                  fillColor: WidgetStateProperty.resolveWith<Color>((states) {
                    if (isSelected) {
                      return getEnteColorScheme(context).primary700;
                    } else {
                      return getEnteColorScheme(context).fillMuted;
                    }
                  }),
                  visualDensity: VisualDensity.compact,
                  splashRadius: 0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    ClipSmoothRect(
                      radius: SmoothBorderRadius(
                        cornerRadius: 12,
                        cornerSmoothing: 1,
                      ),
                      child: Image(
                        width: 60,
                        height: 60,
                        image: AssetImage(appIcon.path),
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOutQuart,
                      switchOutCurve: Curves.easeInQuart,
                      child: Text(
                        key: ValueKey(isSelected),
                        appIcon.name,
                        style: isSelected
                            ? TextStyles.bodyBold.copyWith(
                                color: colors.textBase,
                              )
                            : TextStyles.body.copyWith(color: colors.textLight),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
