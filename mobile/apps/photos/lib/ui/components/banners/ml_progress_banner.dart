import "dart:async";

import "package:ente_components/theme/text_styles.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/events/notification_event.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/ml_model_download_service.dart";
import "package:photos/services/machine_learning/ml_service.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/settings/ml/machine_learning_settings_page.dart";
import "package:photos/utils/ml_util.dart";

class MLProgressBanner extends StatefulWidget {
  const MLProgressBanner({super.key, this.isOnSearchTab});

  final ValueListenable<bool>? isOnSearchTab;

  @override
  State<MLProgressBanner> createState() => _MLProgressBannerState();
}

class _MLProgressBannerState extends State<MLProgressBanner>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  IndexStatus? _indexStatus;
  Timer? _timer;
  bool _dismissed = false;
  bool _indexingComplete = false;
  bool _keepsScreenAwake = false;
  late final StreamSubscription<LocalPhotosUpdatedEvent>
  _localPhotosUpdatedSubscription;
  late final StreamSubscription<NotificationEvent> _notificationSubscription;

  bool get _isOnVisibleTab => widget.isOnSearchTab?.value ?? true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.isOnSearchTab?.addListener(_onSearchTabChanged);
    _localPhotosUpdatedSubscription = Bus.instance
        .on<LocalPhotosUpdatedEvent>()
        .listen((_) {
          _indexingComplete = false;
          _ensurePolling();
        });
    _notificationSubscription = Bus.instance.on<NotificationEvent>().listen((
      _,
    ) {
      _indexingComplete = false;
      _ensurePolling();
      setState(() {});
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
    _updateWakeLock();
  }

  void _onSearchTabChanged() {
    if (_isOnVisibleTab) {
      _ensurePolling();
    } else {
      _stopPolling();
    }
  }

  void _ensurePolling() {
    if (!_isOnVisibleTab) return;
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
      localSettings.isMLLocalIndexingEnabled &&
      !_indexingComplete;

  bool get _isShown {
    final status = _indexStatus;
    return !_dismissed &&
        hasGrantedMLConsent &&
        !localSettings.isMLProgressBannerDismissed &&
        localSettings.isMLLocalIndexingEnabled &&
        status != null &&
        status.pendingItems > 0;
  }

  void _updateWakeLock() {
    final keepScreenAwake =
        (widget.isOnSearchTab?.value ?? false) &&
        _isShown &&
        MLService.instance.isRunningML &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (keepScreenAwake == _keepsScreenAwake) return;
    _keepsScreenAwake = keepScreenAwake;
    wakeLockService.updateWakeLock(
      enable: keepScreenAwake,
      wakeLockFor: WakeLockFor.mlProgressBanner,
    );
  }

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
        _updateWakeLock();
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updateWakeLock();
  }

  @override
  void didUpdateWidget(MLProgressBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isOnSearchTab != widget.isOnSearchTab) {
      oldWidget.isOnSearchTab?.removeListener(_onSearchTabChanged);
      widget.isOnSearchTab?.addListener(_onSearchTabChanged);
      _onSearchTabChanged();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.isOnSearchTab?.removeListener(_onSearchTabChanged);
    _localPhotosUpdatedSubscription.cancel();
    _notificationSubscription.cancel();
    _timer?.cancel();
    if (_keepsScreenAwake) {
      wakeLockService.updateWakeLock(
        enable: false,
        wakeLockFor: WakeLockFor.mlProgressBanner,
      );
    }
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_isShown) return const SizedBox.shrink();

    final status = _indexStatus!;
    final total = status.indexedItems + status.pendingItems;

    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = context.strings;
    final format = NumberFormat();
    final progress = total > 0 ? status.indexedItems.toDouble() / total : 0.0;
    final showModelDownloadPhase = _shouldShowModelDownloadPhase(status);

    final titleStyle = TextStyles.display3.copyWith(
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
