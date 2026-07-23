import 'package:ente_components/ente_components.dart';
import "package:ente_ui/components/captioned_text_widget_v2.dart";
import "package:ente_ui/components/divider_widget.dart";
import "package:ente_ui/components/menu_item_widget_v2.dart";
import "package:ente_ui/components/separators.dart";
import "package:ente_ui/components/title_bar_title_widget.dart";
import "package:ente_ui/components/title_bar_widget.dart";
import 'package:flutter/material.dart';
import "package:locker/l10n/l10n.dart";
import "package:locker/services/collections/collections_api_client.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/ui/viewer/date/date_time_picker.dart";
import "package:locker/utils/error_sheet.dart";
import "package:tuple/tuple.dart";

class LinkExpiryPickerPage extends StatelessWidget {
  final Collection collection;
  const LinkExpiryPickerPage(this.collection, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        primary: false,
        slivers: <Widget>[
          TitleBarWidget(
            flexibleSpaceTitle: TitleBarTitleWidget(
              title: context.l10n.linkExpiry,
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
  // index, title, milliseconds in future post which link should expire (when >0)
  late final List<Tuple2<String, int>> _expiryOptions = [
    Tuple2(context.l10n.never, 0),
    Tuple2(context.l10n.after1Hour, const Duration(hours: 1).inMicroseconds),
    Tuple2(context.l10n.after1Day, const Duration(days: 1).inMicroseconds),
    Tuple2(context.l10n.after1Week, const Duration(days: 7).inMicroseconds),
    // todo: make this time calculation perfect
    Tuple2(context.l10n.after1Month, const Duration(days: 30).inMicroseconds),
    Tuple2(context.l10n.after1Year, const Duration(days: 365).inMicroseconds),
    Tuple2(context.l10n.custom, -1),
  ];

  @override
  Widget build(BuildContext context) {
    List<Widget> items = [];
    for (int index = 0; index < _expiryOptions.length; index++) {
      final expiryOpiton = _expiryOptions[index];
      items.add(
        _menuItemForPicker(
          context,
          expiryOpiton,
          isFirst: index == 0,
          isLast: index == _expiryOptions.length - 1,
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
    BuildContext context,
    Tuple2<String, int> expiryOpiton, {
    required bool isFirst,
    required bool isLast,
  }) {
    return MenuItemWidgetV2(
      menuItemColor: context.componentColors.fillLight,
      captionedTextWidget: CaptionedTextWidgetV2(title: expiryOpiton.item1),
      alignCaptionedTextToLeft: true,
      isTopBorderRadiusRemoved: !isFirst,
      isBottomBorderRadiusRemoved: !isLast,
      alwaysShowSuccessState: true,
      surfaceExecutionStates: expiryOpiton.item2 == -1 ? false : true,
      onTap: () async {
        int newValidTill = -1;
        final int expireAfterInMicroseconds = expiryOpiton.item2;
        // need to manually select time
        if (expireAfterInMicroseconds < 0) {
          final now = DateTime.now();
          final DateTime? picked = await showDatePickerSheet(
            context,
            initialDate: now,
            minDate: now,
          );
          final timeInMicrosecondsFromEpoch = picked?.microsecondsSinceEpoch;
          if (timeInMicrosecondsFromEpoch != null) {
            newValidTill = timeInMicrosecondsFromEpoch;
          }
        } else if (expireAfterInMicroseconds == 0) {
          // no expiry
          newValidTill = 0;
        } else {
          newValidTill =
              DateTime.now().microsecondsSinceEpoch + expireAfterInMicroseconds;
        }
        if (newValidTill >= 0) {
          debugPrint(
            "Setting expire date to  ${DateTime.fromMicrosecondsSinceEpoch(newValidTill)}",
          );
          await updateTime(newValidTill, context.mounted ? context : null);
        }
      },
    );
  }

  Future<void> updateTime(int newValidTill, BuildContext? context) async {
    await _updateUrlSettings(context, {'validTill': newValidTill});
  }

  Future<void> _updateUrlSettings(
    BuildContext? context,
    Map<String, dynamic> prop,
  ) async {
    try {
      await CollectionApiClient.instance.updateShareUrl(
        widget.collection,
        prop,
      );
    } catch (e) {
      if (context != null && context.mounted) {
        await showLockerErrorSheet(context, e);
      }
      rethrow;
    }
  }
}
