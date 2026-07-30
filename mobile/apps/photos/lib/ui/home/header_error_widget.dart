import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import 'package:photos/core/errors.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/ui/payment/subscription.dart';
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
          title: AppLocalizations.of(context).subscribe,
          subtitle: AppLocalizations.of(context).yourSubscriptionHasExpired,
          state: BannerComponentState.failure,
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
          title: AppLocalizations.of(context).upgrade,
          subtitle: AppLocalizations.of(context).storageLimitExceeded,
          state: BannerComponentState.failure,
          onTap: () async {
            await routeToPage(
              context,
              getSubscriptionPage(),
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
          title: AppLocalizations.of(context).backupFailed,
          subtitle: AppLocalizations.of(context).couldNotBackUpTryLater,
          state: BannerComponentState.failure,
          onTap: () {
            sendLogs(
              context,
              AppLocalizations.of(context).raiseTicket,
              "support@ente.com",
              subject: AppLocalizations.of(context).backupFailed,
            );
          },
        ),
      );
    }
  }
}
