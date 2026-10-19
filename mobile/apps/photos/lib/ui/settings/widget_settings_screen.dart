import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/settings/ml/ml_consent_sheet.dart";
import "package:photos/ui/settings/widgets/albums_widget_settings.dart";
import "package:photos/ui/settings/widgets/memories_widget_settings.dart";
import "package:photos/ui/settings/widgets/people_widget_settings.dart";

class WidgetSettingsScreen extends StatelessWidget {
  const WidgetSettingsScreen({super.key});

  Future<void> onPeopleTapped(BuildContext context) async {
    if (!hasGrantedMLConsent) {
      final enabled = await showMLConsentSheet(context);
      if (!enabled || !context.mounted) return;
    }
    unawaited(routeToPage(context, const PeopleWidgetSettings()));
  }

  void onAlbumsTapped(BuildContext context) {
    routeToPage(context, const AlbumsWidgetSettings());
  }

  void onMemoriesTapped(BuildContext context) {
    routeToPage(context, const MemoriesWidgetSettings());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;

    return SettingsPageScaffold(
      title: l10n.widgets,
      children: [
        SettingsItem(
          title: l10n.people,
          svgIconPath: "assets/icons/people-widget-icon.svg",
          showOnlyLoadingState: true,
          onTap: () => unawaited(onPeopleTapped(context)),
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.albums,
          svgIconPath: "assets/icons/albums-widget-icon.svg",
          showOnlyLoadingState: true,
          onTap: () => onAlbumsTapped(context),
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.memories,
          svgIconPath: "assets/icons/memories-widget-icon.svg",
          showOnlyLoadingState: true,
          onTap: () => onMemoriesTapped(context),
        ),
      ],
    );
  }
}
