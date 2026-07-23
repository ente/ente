import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/events/notification_event.dart";
import "package:photos/events/tab_changed_event.dart";
import "package:photos/generated/intl/app_localizations.dart";
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
  static const int _searchTabIndex = 3;

  IndexStatus? _indexStatus;
  Timer? _timer;
  bool _dismissed = false;
  bool _indexingComplete = false;
  bool _isOnSearchTab = true;
  late final StreamSubscription<TabChangedEvent> _tabChangedSubscription;
  late final StreamSubscription<LocalPhotosUpdatedEvent>
  _localPhotosUpdatedSubscription;
  late final StreamSubscription<NotificationEvent> _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _tabChangedSubscription = Bus.instance.on<TabChangedEvent>().listen((
      event,
    ) {
      final wasOnSearchTab = _isOnSearchTab;
      _isOnSearchTab = event.selectedIndex == _searchTabIndex;
      if (_isOnSearchTab && !wasOnSearchTab) {
        _ensurePolling();
      } else if (!_isOnSearchTab && wasOnSearchTab) {
        _stopPolling();
      }
    });
    _localPhotosUpdatedSubscription = Bus.instance
        .on<LocalPhotosUpdatedEvent>()
        .listen((_) {
          _indexStatus = null;
          _indexingComplete = false;
          _ensurePolling();
        });
    _notificationSubscription = Bus.instance.on<NotificationEvent>().listen((
      _,
    ) {
      _indexingComplete = false;
      _ensurePolling();
    });
    _ensurePolling();
  }

  void _startPolling() {
    if (!_shouldPoll) return;
    _fetchStatus();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchStatus();
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void _ensurePolling() {
    if (!_isOnSearchTab) return;
    if (!_shouldPoll) {
      _stopPolling();
      return;
    }
    if (_timer != null) return;
    _startPolling();
  }

  bool get _shouldPoll =>
      !_dismissed &&
      hasGrantedMLConsent &&
      !localSettings.isMLProgressBannerDismissed &&
      !(isLocalGalleryMode && !localSettings.isMLLocalIndexingEnabled) &&
      !_indexingComplete;

  Future<void> _fetchStatus() async {
    try {
      final status = await getIndexStatus();
      if (mounted) {
        setState(() {
          _indexStatus = status;
        });
        if (status.pendingItems <= 0) {
          _indexingComplete = true;
          _stopPolling();
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabChangedSubscription.cancel();
    _localPhotosUpdatedSubscription.cancel();
    _notificationSubscription.cancel();
    _timer?.cancel();
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
    final l10n = AppLocalizations.of(context);
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
    _stopPolling();
    localSettings.setMLProgressBannerDismissed(true);
  }
}
