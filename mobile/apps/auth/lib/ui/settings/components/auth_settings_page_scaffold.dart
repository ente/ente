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
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: AppBarComponent(
        title: title,
        subtitle: subtitle,
        backButton: backButton,
        slivers: [
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList.list(children: children),
            ),
          ),
        ],
      ),
    );
  }
}
