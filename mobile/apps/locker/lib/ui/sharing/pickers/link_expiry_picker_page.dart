import 'package:ente_components/ente_components.dart';
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/date_time_picker.dart";
import 'package:flutter/material.dart';
import "package:locker/services/collections/collections_api_client.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/utils/error_sheet.dart";
import "package:tuple/tuple.dart";

class LinkExpiryPickerPage extends StatelessWidget {
  final Collection collection;
  const LinkExpiryPickerPage(this.collection, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.componentColors.backgroundBase,
      body: AppBarComponent(
        title: context.strings.linkExpiry,
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
  late final List<Tuple2<String, int>> _expiryOptions = [
    Tuple2(context.strings.never, 0),
    Tuple2(context.strings.after1Hour, const Duration(hours: 1).inMicroseconds),
    Tuple2(context.strings.after1Day, const Duration(days: 1).inMicroseconds),
    Tuple2(context.strings.after1Week, const Duration(days: 7).inMicroseconds),
    // todo: make this time calculation perfect
    Tuple2(
      context.strings.after1Month,
      const Duration(days: 30).inMicroseconds,
    ),
    Tuple2(
      context.strings.after1Year,
      const Duration(days: 365).inMicroseconds,
    ),
    Tuple2(context.strings.custom, -1),
  ];

  @override
  Widget build(BuildContext context) {
    return MenuGroupComponent(
      items: [
        for (final expiryOption in _expiryOptions)
          _menuItemForPicker(context, expiryOption),
      ],
    );
  }

  Widget _menuItemForPicker(
    BuildContext context,
    Tuple2<String, int> expiryOption,
  ) {
    return MenuComponent(
      title: expiryOption.item1,
      shouldSurfaceExecutionStates: expiryOption.item2 != -1,
      shouldShowSuccessConfirmation: expiryOption.item2 != -1,
      onTap: () async {
        int newValidTill = -1;
        final int expireAfterInMicroseconds = expiryOption.item2;
        if (expireAfterInMicroseconds < 0) {
          final now = DateTime.now();
          final DateTime? picked = await showDateTimePickerSheet(
            context,
            initialDateTime: now,
            minDateTime: now,
          );
          final timeInMicrosecondsFromEpoch = picked?.microsecondsSinceEpoch;
          if (timeInMicrosecondsFromEpoch != null) {
            newValidTill = timeInMicrosecondsFromEpoch;
          }
        } else if (expireAfterInMicroseconds == 0) {
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
