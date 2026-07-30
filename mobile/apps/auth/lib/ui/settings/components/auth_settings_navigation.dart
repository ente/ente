import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<T?> pushAuthSettingsPage<T extends Object?>(
  BuildContext context,
  Widget page,
) {
  return Navigator.of(context).push<T>(_settingsPageRoute(page));
}

Route<T> _settingsPageRoute<T extends Object?>(Widget page) {
  if (_isDesktop) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, _, _) => page,
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 100),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }
  return MaterialPageRoute<T>(builder: (_) => page);
}

bool get _isDesktop => switch (defaultTargetPlatform) {
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => true,
  _ => false,
};
