import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/settings/app_version_widget.dart';
import 'package:ente_ui/components/settings/social_icons_row.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

class MoreFromEnteFooter extends StatelessWidget {
  const MoreFromEnteFooter({
    super.key,
    required this.currentApp,
    this.onVersionTap,
  });

  final ComponentApp currentApp;
  final VoidCallback? onVersionTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          MoreFromEnteSection(
            currentApp: currentApp,
            moreFromLabel: context.strings.moreFrom,
            onAppTap: (app) {
              launchUrlString(
                _moreFromEnteUri(
                  sourceApp: currentApp,
                  destinationApp: app,
                ).toString(),
                mode: LaunchMode.externalApplication,
              ).ignore();
            },
          ),
          const SizedBox(height: 40),
          const SocialIconsRow(),
          const SizedBox(height: Spacing.md),
          AppVersionWidget(onTap: onVersionTap),
          const SizedBox(height: Spacing.xxl),
        ],
      ),
    );
  }
}

Uri _moreFromEnteUri({
  required ComponentApp sourceApp,
  required ComponentApp destinationApp,
}) {
  final path = switch (destinationApp) {
    ComponentApp.photos => '/',
    ComponentApp.locker => '/locker',
    ComponentApp.auth => '/auth',
  };
  return Uri.https('ente.com', path, {'from': sourceApp.name});
}
