import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class ThemeSelector<T> extends StatelessWidget {
  const ThemeSelector({
    super.key,
    required this.currentMode,
    required this.systemMode,
    required this.lightMode,
    required this.darkMode,
    required this.onChanged,
  });

  final T? currentMode;
  final T systemMode;
  final T lightMode;
  final T darkMode;
  final FutureOr<void> Function(T) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final options = [
      (
        label: strings.systemTheme,
        icon: HugeIcons.strokeRoundedSmartPhone01,
        mode: systemMode,
      ),
      (
        label: strings.lightTheme,
        icon: HugeIcons.strokeRoundedSun03,
        mode: lightMode,
      ),
      (
        label: strings.darkTheme,
        icon: HugeIcons.strokeRoundedMoon02,
        mode: darkMode,
      ),
    ];
    return MenuGroupComponent(
      showDividers: true,
      dividerPadding: const EdgeInsets.only(left: 68),
      items: [
        for (final option in options)
          SettingsItem(
            title: option.label,
            icon: option.icon,
            showChevron: false,
            trailing: currentMode == option.mode
                ? Icon(Icons.check, color: context.componentColors.primary)
                : null,
            onTap: () => onChanged(option.mode),
          ),
      ],
    );
  }
}
