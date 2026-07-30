import 'dart:async';

import "package:ente_components/ente_components.dart";
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";
import 'package:photos/core/event_bus.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/events/christmas_banner_event.dart';
import 'package:photos/events/notification_event.dart';
import 'package:photos/events/sync_status_update_event.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import 'package:photos/services/sync/sync_service.dart';
import "package:photos/theme/ente_theme.dart";
import 'package:photos/ui/account/verify_recovery_page.dart';
import 'package:photos/ui/components/home_header_widget.dart';
import 'package:photos/ui/home/christmas/christmas_lights_banner.dart';
import 'package:photos/ui/home/christmas/christmas_utils.dart';
import 'package:photos/ui/home/header_error_widget.dart';
import "package:photos/ui/settings/backup/backup_settings_screen.dart";
import "package:photos/ui/settings/backup/backup_status_screen.dart";
import "package:photos/ui/settings/ml/machine_learning_settings_page.dart";

const double kContainerHeight = 36;

class StatusBarWidget extends StatefulWidget {
  const StatusBarWidget({super.key});

  @override
  State<StatusBarWidget> createState() => _StatusBarWidgetState();
}

class _StatusBarWidgetState extends State<StatusBarWidget> {
  static final _logger = Logger("StatusBarWidget");

  late StreamSubscription<SyncStatusUpdate> _subscription;
  late StreamSubscription<NotificationEvent> _notificationSubscription;
  late StreamSubscription<ChristmasBannerEvent> _christmasBannerSubscription;
  bool _isPausedDueToNetwork = false;
  bool _showStatus = false;
  bool _showErrorBanner = false;
  bool _showMlBanner =
      !hasGrantedMLConsent &&
      (isLocalGalleryMode || flagService.hasSyncedAccountFlags()) &&
      !localSettings.hasSeenMLEnablingBanner;
  Error? _syncError;

  @override
  void initState() {
    _subscription = Bus.instance.on<SyncStatusUpdate>().listen((event) {
      _logger.info("Received event " + event.status.toString());
      _isPausedDueToNetwork = event.status == SyncStatus.paused;
      if (event.status == SyncStatus.error) {
        setState(() {
          _syncError = event.error;
          _showErrorBanner = true;
        });
      } else {
        setState(() {
          _syncError = null;
          _showErrorBanner = false;
        });
      }
      if (event.status == SyncStatus.completedFirstGalleryImport ||
          event.status == SyncStatus.completedBackup) {
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (mounted) {
            setState(() {
              _showStatus = false;
            });
          }
        });
      } else {
        setState(() {
          _showStatus = true;
        });
      }
    });
    _notificationSubscription = Bus.instance.on<NotificationEvent>().listen((
      event,
    ) {
      if (mounted) {
        _showMlBanner =
            !hasGrantedMLConsent && !localSettings.hasSeenMLEnablingBanner;
        setState(() {});
      }
    });
    _christmasBannerSubscription = Bus.instance
        .on<ChristmasBannerEvent>()
        .listen((_) {
          if (mounted) {
            setState(() {});
          }
        });

    super.initState();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _notificationSubscription.cancel();
    _christmasBannerSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isChristmasPeriod()) const ChristmasLightsBanner(),
        HomeHeaderWidget(
          centerWidget: _showStatus && !_showErrorBanner
              ? GestureDetector(
                  onTap: () {
                    routeToPage(
                      context,
                      _isPausedDueToNetwork
                          ? const BackupSettingsScreen()
                          : const BackupStatusScreen(),
                      forceCustomPageRoute: true,
                    ).ignore();
                  },
                  child: const SyncStatusWidget(),
                )
              : SvgPicture.asset(
                  "assets/ente-branding.svg",
                  height: 15,
                  colorFilter: ColorFilter.mode(
                    Theme.of(context).brightness == Brightness.light
                        ? Colors.black
                        : Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
        ),
        _showErrorBanner
            ? Divider(height: 8, color: getEnteColorScheme(context).strokeFaint)
            : const SizedBox.shrink(),
        if (_showErrorBanner) HeaderErrorWidget(error: _syncError),
        if (_showMlBanner && !_showErrorBanner) _mlBanner(context),
        if (_showVerificationBanner()) _recoveryKeyBanner(context),
      ],
    );
  }

  Widget _mlBanner(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _bannerPadding(
      BannerComponent(
        leadingIcon: HugeIcons.strokeRoundedAiBrain01,
        title: l10n.machineLearning,
        subtitle: l10n.machineLearningBannerSubtitle,
        state: BannerComponentState.success,
        onTap: () async {
          await routeToPage(
            context,
            const MachineLearningSettingsPage(),
            forceCustomPageRoute: true,
          );
        },
      ),
    );
  }

  Widget _recoveryKeyBanner(BuildContext context) {
    return _bannerPadding(
      BannerComponent(
        leadingIcon: HugeIcons.strokeRoundedAlertCircle,
        title: AppLocalizations.of(context).confirmYourRecoveryKey,
        state: BannerComponentState.warning,
        onTap: () async {
          await routeToPage(
            context,
            const VerifyRecoveryPage(),
            forceCustomPageRoute: true,
          );
        },
      ),
    );
  }

  Widget _bannerPadding(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: child,
    );
  }

  // _showVerificationBanner after 3 days of installation
  bool _showVerificationBanner() {
    if (_showErrorBanner ||
        _showErrorBanner ||
        flagService.recoveryKeyVerified) {
      return false;
    }
    final DateTime installTime = localSettings.getInstallDateTime();
    return DateTime.now().difference(installTime).inDays >= 3;
  }
}

class SyncStatusWidget extends StatefulWidget {
  const SyncStatusWidget({super.key});

  @override
  State<SyncStatusWidget> createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  static const Duration kSleepDuration = Duration(milliseconds: 3000);

  SyncStatusUpdate? _event;
  late StreamSubscription<SyncStatusUpdate> _subscription;

  @override
  void initState() {
    _subscription = Bus.instance.on<SyncStatusUpdate>().listen((event) {
      setState(() {
        _event = event;
      });
    });
    _event = SyncService.instance.getLastSyncStatusEvent();
    super.initState();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isNotOutdatedEvent =
        _event != null &&
        (_event!.status == SyncStatus.completedBackup ||
            _event!.status == SyncStatus.completedFirstGalleryImport) &&
        (DateTime.now().microsecondsSinceEpoch - _event!.timestamp >
            kSleepDuration.inMicroseconds);
    if (_event == null ||
        isNotOutdatedEvent ||
        //sync error cases are handled in StatusBarWidget
        _event!.status == SyncStatus.error) {
      return const SizedBox.shrink();
    }
    if (_event!.status == SyncStatus.completedBackup) {
      return const SyncStatusCompletedWidget();
    }
    return RefreshIndicatorWidget(_getRefreshingText(context));
  }

  String _getRefreshingText(BuildContext context) {
    if (_event == null) {
      return AppLocalizations.of(context).loadingGallery;
    }
    if (_event!.status == SyncStatus.startedFirstGalleryImport ||
        _event!.status == SyncStatus.completedFirstGalleryImport) {
      return AppLocalizations.of(context).loadingGallery;
    }
    if (_event!.status == SyncStatus.applyingRemoteDiff) {
      return AppLocalizations.of(context).syncing;
    }
    if (_event!.status == SyncStatus.preparingForUpload) {
      if (_event!.total == null || _event!.total! <= 0) {
        return AppLocalizations.of(context).encryptingBackup;
      } else if (_event!.total == 1) {
        return AppLocalizations.of(context).uploadingSingleMemory;
      } else {
        return AppLocalizations.of(context).uploadingMultipleMemories(
          count: NumberFormat().format(_event!.total!),
        );
      }
    }
    if (_event!.status == SyncStatus.inProgress) {
      final format = NumberFormat();
      return AppLocalizations.of(context).syncProgress(
        completed: format.format(_event!.completed!),
        total: format.format(_event!.total!),
      );
    }
    if (_event!.status == SyncStatus.paused) {
      return _event!.reason;
    }
    if (_event!.status == SyncStatus.error) {
      return _event!.reason;
    }
    if (_event!.status == SyncStatus.completedBackup) {
      if (_event!.wasStopped) {
        return AppLocalizations.of(context).syncStopped;
      }
    }
    return AppLocalizations.of(context).allMemoriesPreserved;
  }
}

class RefreshIndicatorWidget extends StatelessWidget {
  static const _inProgressIcon = CircularProgressIndicator(
    strokeWidth: 2,
    valueColor: AlwaysStoppedAnimation<Color>(Color.fromRGBO(45, 194, 98, 1.0)),
  );

  final String text;

  const RefreshIndicatorWidget(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kContainerHeight,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  width: 22,
                  height: 22,
                  child: _inProgressIcon,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
                  child: Text(text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SyncStatusCompletedWidget extends StatelessWidget {
  const SyncStatusCompletedWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.defaultBackgroundColor,
      height: kContainerHeight,
      child: Align(
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                  color: Theme.of(context).colorScheme.greenAlternative,
                  size: 22,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    AppLocalizations.of(context).allMemoriesPreserved,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
