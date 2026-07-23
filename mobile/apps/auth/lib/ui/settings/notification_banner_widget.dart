import 'package:ente_accounts/models/user_details.dart';
import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/services/update_service.dart';
import 'package:ente_auth/ui/components/banner_widget.dart';
import 'package:flutter/material.dart';

class NotificationBannerWidget extends StatelessWidget {
  const NotificationBannerWidget({super.key});

  static const _showDiscountOffer = false;

  @override
  Widget build(BuildContext context) {
    List<Widget> contents = [];
    const sectionSpacing = SizedBox(height: 14);
    final currentTime = DateTime.now();
    final appInstallTime = PreferenceService.instance.getAppInstalledTime();
    final differenceInDays = currentTime
        .difference(DateTime.fromMillisecondsSinceEpoch(appInstallTime))
        .inDays;
    final l10n = context.l10n;
    final ratePlace = UpdateService.instance.getRateDetails().item1;
    final rateSubText = l10n.rateUsOnStore(ratePlace);

    if (Configuration.instance.hasConfiguredAccount()) {
      return FutureBuilder<UserDetails>(
        future: UserService.instance.getUserDetailsV2(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final userDetails = snapshot.data;

            if (differenceInDays >= 0 && differenceInDays <= 3) {
              return const SizedBox.shrink();
            } else if (differenceInDays >= 4 && differenceInDays <= 7) {
              contents.clear();
              contents.addAll([
                BannerWidget(
                  text: l10n.tellUsWhatYouThink,
                  subText: rateSubText,
                  type: BannerType.rateUs,
                ),
                sectionSpacing,
                BannerWidget(
                  text: l10n.supportEnte,
                  subText: l10n.giveUsAStarOnGithub,
                  type: BannerType.starUs,
                ),
              ]);
              return buildWidget(context, contents);
            } else if (differenceInDays >= 7 && differenceInDays <= 30) {
              if (userDetails?.usage == 0) {
                contents.clear();
                contents.addAll([
                  BannerWidget(
                    text: l10n.free10GB,
                    subText: l10n.loginWithAuthAccount,
                    type: BannerType.freeStorage,
                  ),
                ]);
              } else if (_showDiscountOffer &&
                  (userDetails!.usage < 5 * 1024 * 1024 * 1024 ||
                      userDetails.subscription.productID == 'free')) {
                contents.addAll([
                  BannerWidget(
                    text: l10n.freeStorageOffer,
                    subText: l10n.freeStorageOfferDescription,
                    type: BannerType.discount,
                  ),
                ]);
              }
              return buildWidget(context, contents);
            }
          }
          return const SizedBox.shrink();
        },
      );
    } else {
      if (differenceInDays >= 4 && differenceInDays <= 7) {
        contents.clear();
        contents.addAll([
          BannerWidget(
            text: l10n.tellUsWhatYouThink,
            subText: rateSubText,
            type: BannerType.rateUs,
          ),
          sectionSpacing,
          BannerWidget(
            text: l10n.supportEnte,
            subText: l10n.giveUsAStarOnGithub,
            type: BannerType.starUs,
          ),
        ]);
      }
      return buildWidget(context, contents);
    }
  }

  Widget buildWidget(BuildContext context, List<Widget> contents) {
    return Column(children: contents);
  }
}
