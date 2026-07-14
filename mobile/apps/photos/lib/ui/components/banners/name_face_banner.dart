import "dart:async";

import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/app_mode_changed_event.dart";
import "package:photos/generated/intl/app_localizations.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/account/email_entry_page.dart";
import "package:photos/ui/components/banners/banner_action_button.dart";

class NameFaceBanner extends StatefulWidget {
  const NameFaceBanner({super.key});

  @override
  State<NameFaceBanner> createState() => _NameFaceBannerState();
}

class _NameFaceBannerState extends State<NameFaceBanner> {
  bool _dismissed = false;
  late StreamSubscription<AppModeChangedEvent> _appModeChangedEvent;

  @override
  void initState() {
    super.initState();
    _appModeChangedEvent = Bus.instance.on<AppModeChangedEvent>().listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _appModeChangedEvent.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    if (!(isLocalGalleryMode &&
        !Configuration.instance.hasConfiguredAccount())) {
      return const SizedBox.shrink();
    }
    if (localSettings.isLocalGalleryNameFaceBannerDismissed) {
      return const SizedBox.shrink();
    }

    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: colorScheme.backgroundColour,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      l10n.offlineNameFaceBannerTitle,
                      textAlign: TextAlign.center,
                      style: textTheme.largeBold.copyWith(
                        fontFamily: "Nunito",
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        height: 24 / 18,
                        letterSpacing: -1,
                        color: colorScheme.textBase,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _onDismiss,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.fillDark,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedCancel01,
                          color: colorScheme.contentLight,
                          size: 18,
                          strokeWidth: 2.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                l10n.offlineNameFaceBannerSubtitle,
                textAlign: TextAlign.center,
                style: textTheme.smallMuted,
              ),
            ),
            const SizedBox(height: 16),
            BannerActionButton(
              label: l10n.signUp,
              onTap: () {
                routeToPage(
                  context,
                  const EmailEntryPage(
                    showReferralSourceField: false,
                    referralSource: "Offline",
                  ),
                );
              },
              variant: BannerActionButtonVariant.primary,
            ),
          ],
        ),
      ),
    );
  }

  void _onDismiss() {
    setState(() {
      _dismissed = true;
    });
    localSettings.setLocalGalleryNameFaceBannerDismissed(true);
  }
}
