import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/components/alert_bottom_sheet.dart";
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import "package:photos/ui/settings/developer_settings_page.dart";

class DeveloperSettingsTapArea extends StatefulWidget {
  const DeveloperSettingsTapArea({
    super.key,
    this.child = const SizedBox.expand(),
    this.behavior = HitTestBehavior.opaque,
    this.onSettingsChanged,
  });

  final Widget child;
  final HitTestBehavior behavior;
  final VoidCallback? onSettingsChanged;

  @override
  State<DeveloperSettingsTapArea> createState() =>
      _DeveloperSettingsTapAreaState();
}

class _DeveloperSettingsTapAreaState extends State<DeveloperSettingsTapArea> {
  static const _tapCountThreshold = 7;

  int _tapCount = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTap: _handleTap,
      child: widget.child,
    );
  }

  Future<void> _handleTap() async {
    _tapCount++;
    if (_tapCount < _tapCountThreshold) {
      return;
    }
    _tapCount = 0;

    await showAlertBottomSheet(
      context,
      title: AppLocalizations.of(context).developerSettings,
      message: AppLocalizations.of(context).developerSettingsWarning,
      assetPath: "assets/warning-grey.png",
      isDismissible: false,
      buttons: [
        ButtonWidgetV2(
          buttonType: ButtonTypeV2.primary,
          labelText: AppLocalizations.of(context).yes,
          onTap: () async {
            Navigator.of(context).pop();
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeveloperSettingsPage()),
            );
            widget.onSettingsChanged?.call();
          },
        ),
      ],
    );
  }
}
