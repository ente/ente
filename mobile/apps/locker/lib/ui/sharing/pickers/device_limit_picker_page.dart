import 'package:ente_components/ente_components.dart';
import "package:ente_ui/components/captioned_text_widget_v2.dart";
import "package:ente_ui/components/divider_widget.dart";
import "package:ente_ui/components/menu_item_widget_v2.dart";
import "package:ente_ui/components/separators.dart";
import "package:ente_ui/components/title_bar_title_widget.dart";
import "package:ente_ui/components/title_bar_widget.dart";
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
      body: CustomScrollView(
        primary: false,
        slivers: <Widget>[
          TitleBarWidget(
            flexibleSpaceTitle: TitleBarTitleWidget(
              title: context.l10n.linkDeviceLimit,
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      child: ItemsWidget(collection),
                    ),
                  ],
                ),
              );
            }, childCount: 1),
          ),
          const SliverPadding(padding: EdgeInsets.symmetric(vertical: 12)),
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
  List<Widget> items = [];
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
    items.clear();
    if (isCustomLimit) {
      items.add(
        _menuItemForPicker(
          initialDeviceLimit,
          isFirst: true,
          isLast: publicLinkDeviceLimits.isEmpty,
        ),
      );
    }
    for (int index = 0; index < publicLinkDeviceLimits.length; index++) {
      final deviceLimit = publicLinkDeviceLimits[index];
      items.add(
        _menuItemForPicker(
          deviceLimit,
          isFirst: !isCustomLimit && index == 0,
          isLast: index == publicLinkDeviceLimits.length - 1,
        ),
      );
    }
    items = addSeparators(
      items,
      DividerWidget(
        dividerType: DividerType.menuNoIcon,
        bgColor: context.componentColors.fillLight,
      ),
    );
    return Column(mainAxisSize: MainAxisSize.min, children: items);
  }

  Widget _menuItemForPicker(
    int deviceLimit, {
    required bool isFirst,
    required bool isLast,
  }) {
    return MenuItemWidgetV2(
      key: ValueKey(deviceLimit),
      menuItemColor: context.componentColors.fillLight,
      captionedTextWidget: CaptionedTextWidgetV2(
        title: deviceLimit == 0 ? context.l10n.noDeviceLimit : "$deviceLimit",
      ),
      trailingIcon: currentDeviceLimit == deviceLimit ? Icons.check : null,
      alignCaptionedTextToLeft: true,
      isTopBorderRadiusRemoved: !isFirst,
      isBottomBorderRadiusRemoved: !isLast,
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
