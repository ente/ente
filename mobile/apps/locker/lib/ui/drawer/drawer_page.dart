import "package:ente_components/ente_components.dart";
import "package:ente_sharing/verify_identity_dialog.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/pages/settings_search_page.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/services/configuration.dart";
import "package:locker/ui/components/legacy_collections_trash_widget.dart";
import "package:locker/ui/components/usage_card_widget.dart";
import "package:locker/ui/settings/search/settings_search_registry.dart";
import "package:locker/ui/settings/settings_page.dart";

class DrawerPage extends StatelessWidget {
  final ValueNotifier<String?> emailNotifier;
  final GlobalKey<ScaffoldState> scaffoldKey;

  const DrawerPage({
    super.key,
    required this.emailNotifier,
    required this.scaffoldKey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: Container(color: colors.backgroundBase, child: _getBody(context)),
    );
  }

  Widget _getBody(BuildContext context) {
    final hasLoggedIn = Configuration.instance.hasConfiguredAccount();
    final List<Widget> contents = [];

    if (hasLoggedIn) {
      contents.addAll([
        const UsageCardWidget(),
        const SizedBox(height: 24),
        const LegacyCollectionsTrashWidget(),
        const SizedBox(height: 24),
      ]);
    }

    contents.addAll([
      SettingsWidget(hasLoggedIn: hasLoggedIn),
      const Padding(padding: EdgeInsets.only(bottom: 60)),
    ]);

    return AnimatedBuilder(
      animation: emailNotifier,
      builder: (context, _) {
        final email = emailNotifier.value ?? "";
        final title = hasLoggedIn && email.isNotEmpty
            ? email
            : context.strings.settings;

        return AppBarComponent(
          title: title,
          actions: [_buildSearchAction(context)],
          onBack: () => scaffoldKey.currentState?.closeDrawer(),
          onTitleDoubleTap: hasLoggedIn
              ? () => _showVerifyIDSheet(context)
              : null,
          onTitleLongPress: hasLoggedIn
              ? () => _showVerifyIDSheet(context)
              : null,
          slivers: [
            SliverSafeArea(
              top: false,
              sliver: SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.list(children: contents),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchAction(BuildContext context) {
    return IconButtonComponent(
      tooltip: context.strings.search,
      variant: IconButtonComponentVariant.primary,
      shouldSurfaceExecutionStates: false,
      onTap: () => _openSearch(context),
      icon: const HugeIcon(
        icon: HugeIcons.strokeRoundedSearch01,
        size: IconSizes.small,
        strokeWidth: 1.75,
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          final items = SettingsSearchRegistry.getSearchableItems(context);
          return SettingsSearchPage(
            items: items,
            suggestions: SettingsSearchRegistry.getSuggestions(context, items),
            onNavigate: (context, routeBuilder) => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: routeBuilder)),
          );
        },
      ),
    );
  }

  void _showVerifyIDSheet(BuildContext context) {
    showVerifyIdentitySheet(
      context,
      self: true,
      config: Configuration.instance,
      title: context.strings.verifyIDLabel,
    );
  }
}
