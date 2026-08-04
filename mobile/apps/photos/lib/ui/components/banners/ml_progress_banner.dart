import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/notification_event.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/ml_model_download_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/settings/ml/machine_learning_settings_page.dart";
import "package:photos/utils/ml_util.dart";

class MLProgressBanner extends StatefulWidget {
  const MLProgressBanner({super.key});

  @override
  State<MLProgressBanner> createState() => _MLProgressBannerState();
}

class _MLProgressBannerState extends State<MLProgressBanner> {
  IndexStatus? _indexStatus;
  bool _dismissed = false;
  StreamSubscription<IndexStatus>? _statusSubscription;
  StreamSubscription<NotificationEvent>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    if (localSettings.isMLProgressBannerDismissed) {
      return;
    }
    _statusSubscription = mlIndexStatusService.statusStream.listen((status) {
      if (mounted) setState(() => _indexStatus = status);
    });
    _notificationSubscription = Bus.instance.on<NotificationEvent>().listen((
      _,
    ) {
      // ML consent or related settings may have changed.
      if (mounted) setState(() {});
      unawaited(_fetchStatusIfEligible());
    });
    unawaited(_fetchStatusIfEligible());
  }

  bool get _isEligible =>
      !_dismissed &&
      hasGrantedMLConsent &&
      !localSettings.isMLProgressBannerDismissed &&
      !(isLocalGalleryMode && !localSettings.isMLLocalIndexingEnabled);

  Future<void> _fetchStatusIfEligible() async {
    if (!_isEligible) return;
    try {
      final status = await mlIndexStatusService.getStatus();
      if (mounted) setState(() => _indexStatus = status);
    } catch (_) {}
  }

  void _cancelSubscriptions() {
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    if (!hasGrantedMLConsent) return const SizedBox.shrink();
    if (localSettings.isMLProgressBannerDismissed) {
      return const SizedBox.shrink();
    }
    if (isLocalGalleryMode && !localSettings.isMLLocalIndexingEnabled) {
      return const SizedBox.shrink();
    }

    final status = _indexStatus;
    if (status == null) return const SizedBox.shrink();
    if (status.pendingItems <= 0) return const SizedBox.shrink();

    final total = status.indexedItems + status.pendingItems;
    if (total <= 0) return const SizedBox.shrink();

    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = context.strings;
    final format = NumberFormat();
    final progress = total > 0 ? status.indexedItems.toDouble() / total : 0.0;
    final showModelDownloadPhase = _shouldShowModelDownloadPhase(status);

    final titleStyle = textTheme.largeBold.copyWith(
      fontFamily: "Nunito",
      fontWeight: FontWeight.w800,
      fontSize: 20,
      height: 24 / 18,
      letterSpacing: -1,
      color: colorScheme.greenBase,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          routeToPage(context, const MachineLearningSettingsPage());
        },
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.backgroundElevated2,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.mlProgressBannerTitle, style: titleStyle),
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
                          color: colorScheme.contentDark,
                          size: 18,
                          strokeWidth: 2.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.mlProgressBannerDescription,
                style: textTheme.smallMuted,
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(2.5),
                child: LinearProgressIndicator(
                  value: showModelDownloadPhase ? 0.0 : progress,
                  minHeight: 4,
                  backgroundColor: colorScheme.fillFaint,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.greenBase,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  showModelDownloadPhase
                      ? l10n.loadingModel
                      : l10n.mlProgressBannerStatus(
                          indexed: format.format(status.indexedItems),
                          total: format.format(total),
                        ),
                  style: textTheme.miniMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _shouldShowModelDownloadPhase(IndexStatus status) {
    if (!localSettings.isMLLocalIndexingEnabled) return false;
    if (status.indexedItems > 0) return false;
    if (status.pendingItems <= 0) return false;
    return !MLModelDownloadService.instance.areModelsDownloaded(
      onlyIndexingModels: true,
    );
  }

  void _onDismiss() {
    setState(() {
      _dismissed = true;
    });
    _cancelSubscriptions();
    localSettings.setMLProgressBannerDismissed(true);
  }
}
