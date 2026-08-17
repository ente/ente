import 'dart:math' as math;

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';

class AuthSettingsPageScaffold extends StatelessWidget {
  const AuthSettingsPageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.backButton,
  });

  final String title;
  final String? subtitle;
  final Widget? backButton;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rightPadding = math.max(
          Spacing.lg,
          constraints.maxWidth - Spacing.lg - _maxContentWidth,
        );

        return SettingsPageScaffold(
          title: title,
          subtitle: subtitle,
          backButton: backButton,
          padding: EdgeInsets.fromLTRB(Spacing.lg, 0, rightPadding, Spacing.lg),
          children: children,
        );
      },
    );
  }
}

const double _maxContentWidth = 720;
