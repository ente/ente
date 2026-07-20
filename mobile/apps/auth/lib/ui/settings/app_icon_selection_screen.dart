import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_components/ente_components.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:launcher_icon_switcher/launcher_icon_switcher.dart';
import 'package:logging/logging.dart';

enum AppIcon {
  iconDefault(
    "Default",
    "IconDefault",
    "assets/launcher_icon/icon-default.png",
  ),
  iconLight("Light", "IconLight", "assets/launcher_icon/icon-light.png"),
  iconDark("Dark", "IconDark", "assets/launcher_icon/icon-dark.png"),
  iconOG("Shield", "IconOG", "assets/launcher_icon/icon-og.png");

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
  // ignore: prefer_final_fields
  bool _isChangingIcon = false;

  @override
  void initState() {
    super.initState();
    _iconSwitcher.initialize(
      AppIcon.values.map((e) => e.id).toList(),
      AppIcon.iconDefault.id,
    );
    _iconSwitcher
        .getCurrentIcon()
        .then((icon) {
          _logger.info("Current icon is $icon");
          if (!mounted) return;
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
    final l10n = context.l10n;
    return AuthSettingsPageScaffold(
      title: l10n.appIcon,
      children: [
        if (_currentIcon == null)
          const Padding(
            padding: EdgeInsets.all(Spacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Semantics(
            identifier: 'auth_app_icon_list',
            child: MenuGroupComponent(
              showDividers: true,
              dividerPadding: const EdgeInsets.only(left: 64),
              items: [
                for (final icon in AppIcon.values)
                  _AppIconTile(
                    icon,
                    icon.id == _currentIcon,
                    () => icon.id == _currentIcon
                        ? Future<void>.value()
                        : _changeIcon(icon.id),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _changeIcon(String icon) async {
    if (_isChangingIcon) return;
    setState(() {
      _isChangingIcon = true;
    });
    try {
      _logger.info("Changing icon to $icon");
      await _iconSwitcher.setIcon(icon);
      _logger.info("Icon changed to $icon");
      if (!mounted) return;
      setState(() {
        _currentIcon = icon;
      });
    } catch (error, stackTrace) {
      _logger.severe("Error changing icon", error, stackTrace);
    } finally {
      if (mounted) setState(() => _isChangingIcon = false);
    }
  }
}

class _AppIconTile extends StatelessWidget {
  final AppIcon appIcon;
  final bool isSelected;
  final Future<void> Function() onSelect;
  const _AppIconTile(this.appIcon, this.isSelected, this.onSelect);

  @override
  Widget build(BuildContext context) {
    return MenuComponent(
      title: appIcon.name,
      selected: isSelected,
      leading: ClipSmoothRect(
        radius: SmoothBorderRadius(cornerRadius: 8, cornerSmoothing: 1),
        child: Image(width: 36, height: 36, image: AssetImage(appIcon.path)),
      ),
      trailing: RadioComponent(
        selected: isSelected,
        onChanged: (_) => onSelect(),
      ),
      onTap: onSelect,
    );
  }
}
