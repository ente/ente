import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/ui/common/web_page.dart';
import 'package:photos/ui/sharing/share_components.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:photos/utils/public_link_layout_util.dart';
import 'package:tuple/tuple.dart';

class LayoutPickerPage extends StatelessWidget {
  final Collection collection;
  const LayoutPickerPage(this.collection, {super.key});

  @override
  Widget build(BuildContext context) {
    return ShareScaffold(
      title: AppLocalizations.of(context).albumLayout,
      actions: [
        IconButtonComponent(
          variant: IconButtonComponentVariant.primary,
          tooltip: AppLocalizations.of(context).preview,
          shouldSurfaceExecutionStates: false,
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedView),
          onTap: () async {
            await _openPublicAlbumPreview(context);
          },
        ),
      ],
      children: [ItemsWidget(collection)],
    );
  }

  Future<void> _openPublicAlbumPreview(BuildContext context) async {
    try {
      final String publicUrl = CollectionsService.instance.getPublicUrl(
        collection,
      );
      await routeToPage(
        context,
        WebPage(
          AppLocalizations.of(context).preview,
          publicUrl,
          canOpenInBrowser: false,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }
}

class ItemsWidget extends StatefulWidget {
  final Collection collection;
  const ItemsWidget(this.collection, {super.key});

  @override
  State<ItemsWidget> createState() => _ItemsWidgetState();
}

class _ItemsWidgetState extends State<ItemsWidget> {
  late String currentLayout;
  late final List<Tuple2<String, String>> _layoutOptions = [
    Tuple2(AppLocalizations.of(context).layoutMasonry, "masonry"),
    Tuple2(AppLocalizations.of(context).layoutTrip, "trip"),
    Tuple2(AppLocalizations.of(context).layoutGrouped, "grouped"),
  ];

  @override
  void initState() {
    currentLayout = normalizePublicLinkLayout(
      widget.collection.pubMagicMetadata.layout,
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final layoutOption in _layoutOptions)
        _menuItemForPicker(context, layoutOption),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShareMenuGroup(items: items),
        if (currentLayout == "trip")
          ShareSectionDescription(
            AppLocalizations.of(context).mapsPrivacyNotice,
          ),
      ],
    );
  }

  Widget _menuItemForPicker(
    BuildContext context,
    Tuple2<String, String> layoutOption,
  ) {
    return ShareMenuItem(
      title: layoutOption.item1,
      trailing: currentLayout == layoutOption.item2
          ? shareCheck(context)
          : null,
      shouldSurfaceExecutionStates: true,
      shouldShowSuccessConfirmation: true,
      onTap: () async {
        await updateLayout(layoutOption.item2, context);
      },
    );
  }

  Future<void> updateLayout(String newLayout, BuildContext context) async {
    await _updateLayoutSettings(context, {'layout': newLayout}).then(
      (value) => setState(() {
        currentLayout = newLayout;
      }),
    );
  }

  Future<void> _updateLayoutSettings(
    BuildContext context,
    Map<String, dynamic> prop,
  ) async {
    try {
      await CollectionsService.instance.updatePublicMagicMetadata(
        widget.collection,
        prop,
      );
    } catch (e) {
      if (context.mounted) {
        await showGenericErrorDialog(context: context, error: e);
      }
      rethrow;
    }
  }
}
