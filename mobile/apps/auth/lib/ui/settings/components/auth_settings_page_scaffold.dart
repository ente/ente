import 'dart:math' as math;

import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';

/// Auth-local settings scaffold composed from [AppBarComponent].
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
    final colors = context.componentColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rightPadding = math.max(
          Spacing.lg,
          constraints.maxWidth - Spacing.lg - _maxContentWidth,
        );

        return Scaffold(
          backgroundColor: colors.backgroundBase,
          body: AppBarComponent(
            title: title,
            subtitle: subtitle,
            backButton: backButton,
            horizontalPadding: Spacing.lg,
            slivers: [
              SliverSafeArea(
                top: false,
                sliver: SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    Spacing.lg,
                    0,
                    rightPadding,
                    Spacing.lg,
                  ),
                  sliver: SliverList.list(children: children),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

const double _maxContentWidth = 720;
