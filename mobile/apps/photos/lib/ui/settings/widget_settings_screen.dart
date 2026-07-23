import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/settings/components/settings_item.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/ui/settings/ml/machine_learning_settings_page.dart";
import "package:photos/ui/settings/widgets/albums_widget_settings.dart";
import "package:photos/ui/settings/widgets/memories_widget_settings.dart";
import "package:photos/ui/settings/widgets/people_widget_settings.dart";

class WidgetSettingsScreen extends StatelessWidget {
  const WidgetSettingsScreen({super.key});

  void onPeopleTapped(BuildContext context) {
    final bool isMLEnabled = !hasGrantedMLConsent;
    if (isMLEnabled) {
      routeToPage(
        context,
        const MachineLearningSettingsPage(),
        forceCustomPageRoute: true,
      );
      return;
    }
    routeToPage(context, const PeopleWidgetSettings());
  }

  void onAlbumsTapped(BuildContext context) {
    routeToPage(context, const AlbumsWidgetSettings());
  }

  void onMemoriesTapped(BuildContext context) {
    routeToPage(context, const MemoriesWidgetSettings());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SettingsPageScaffold(
      title: l10n.widgets,
      children: [
        SettingsItem(
          title: l10n.people,
          svgIconPath: "assets/icons/people-widget-icon.svg",
          showOnlyLoadingState: true,
          onTap: () => onPeopleTapped(context),
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
