import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import 'package:photos/core/errors.dart';
import 'package:photos/ui/payment/subscription.dart';
import "package:photos/ui/settings/backup/free_space_options.dart";
import 'package:photos/utils/email_util.dart';

class HeaderErrorWidget extends StatelessWidget {
  final Error? _error;

  const HeaderErrorWidget({super.key, required Error? error}) : _error = error;

  @override
  Widget build(BuildContext context) {
    if (_error is NoActiveSubscriptionError) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
        child: BannerComponent(
          leadingIcon: HugeIcons.strokeRoundedInformationCircle,
          title: context.strings.subscribe,
          subtitle: context.strings.yourSubscriptionHasExpired,
          state: BannerComponentState.failure,
          trailingWidget: const Icon(Icons.arrow_forward),
          onTap: () async {
            await routeToPage(
              context,
              getSubscriptionPage(),
              forceCustomPageRoute: true,
            );
          },
        ),
      );
    } else if (_error is StorageLimitExceededError) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
        child: BannerComponent(
          leadingIcon: HugeIcons.strokeRoundedDatabase,
          title: context.strings.upgrade,
          subtitle: context.strings.storageLimitExceeded,
          state: BannerComponentState.failure,
          trailingWidget: const Icon(Icons.arrow_forward),
          onTap: () async {
            await routeToPage(
              context,
              getSubscriptionPage(),
              forceCustomPageRoute: true,
            );
          },
        ),
      );
    } else if (_error is DeviceStorageFullError) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
        child: BannerComponent(
          leadingIcon: HugeIcons.strokeRoundedAlertCircle,
          title: context.strings.freeUpDeviceSpace,
          subtitle: context.strings.backupPausedFreeUpDeviceStorage,
          state: BannerComponentState.failure,
          trailingWidget: const Icon(Icons.arrow_forward),
          onTap: () async {
            await routeToPage(
              context,
              const FreeUpSpaceOptionsScreen(),
              forceCustomPageRoute: true,
            );
          },
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
        child: BannerComponent(
          leadingIcon: HugeIcons.strokeRoundedAlertCircle,
          title: context.strings.backupFailed,
          subtitle: context.strings.couldNotBackUpTryLater,
          state: BannerComponentState.failure,
          trailingWidget: const Icon(Icons.arrow_forward),
          onTap: () {
            sendLogs(
              context,
              context.strings.raiseTicket,
              "support@ente.com",
              subject: context.strings.backupFailed,
            );
          },
        ),
      );
    }
  }
}
