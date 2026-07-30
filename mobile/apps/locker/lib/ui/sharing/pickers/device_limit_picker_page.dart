import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import "package:locker/core/constants.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/services/collections/collections_api_client.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/utils/error_sheet.dart";

class DeviceLimitPickerPage extends StatelessWidget {
  final Collection collection;
  const DeviceLimitPickerPage(this.collection, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.componentColors.backgroundBase,
      body: AppBarComponent(
        title: context.l10n.linkDeviceLimit,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.xl,
              Spacing.lg,
              Spacing.xl,
            ),
            sliver: SliverToBoxAdapter(child: ItemsWidget(collection)),
          ),
        ],
      ),
    );
  }
}

class ItemsWidget extends StatefulWidget {
  final Collection collection;
  const ItemsWidget(this.collection, {super.key});

  @override
  State<ItemsWidget> createState() => _ItemsWidgetState();
}

class _ItemsWidgetState extends State<ItemsWidget> {
  late int currentDeviceLimit;
  late int initialDeviceLimit;
  bool isCustomLimit = false;
  @override
  void initState() {
    currentDeviceLimit = widget.collection.publicURLs.first.deviceLimit;
    initialDeviceLimit = currentDeviceLimit;
    if (!publicLinkDeviceLimits.contains(currentDeviceLimit)) {
      isCustomLimit = true;
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    if (isCustomLimit) {
      items.add(_menuItemForPicker(initialDeviceLimit));
    }
    for (final deviceLimit in publicLinkDeviceLimits) {
      items.add(_menuItemForPicker(deviceLimit));
    }
    return MenuGroupComponent(items: items);
  }

  Widget _menuItemForPicker(int deviceLimit) {
    return MenuComponent(
      key: ValueKey(deviceLimit),
      title: deviceLimit == 0 ? context.l10n.noDeviceLimit : "$deviceLimit",
      trailing: currentDeviceLimit == deviceLimit
          ? Icon(Icons.check, color: context.componentColors.primary)
          : null,
      showOnlyLoadingState: true,
      onTap: () async {
        await _updateUrlSettings(context, {'deviceLimit': deviceLimit});
        if (!mounted) {
          return;
        }
        setState(() {
          currentDeviceLimit = deviceLimit;
        });
      },
    );
  }

  Future<void> _updateUrlSettings(
    BuildContext context,
    Map<String, dynamic> prop,
  ) async {
    try {
      await CollectionApiClient.instance.updateShareUrl(
        widget.collection,
        prop,
      );
    } catch (e) {
      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
      rethrow;
    }
  }
}
