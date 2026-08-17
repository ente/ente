import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_screen_brightness/ente_screen_brightness.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/force_reload_home_gallery_event.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/sync/large_backup_session_tracker.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/ui/components/alert_bottom_sheet.dart";
import "package:rive/rive.dart" as rive;

Future<void> showLargeBackupScreen(
  BuildContext context,
  LargeBackupSessionTracker sessionTracker,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LargeBackupScreen(sessionTracker: sessionTracker),
    ),
  );
}

class LargeBackupScreen extends StatefulWidget {
  const LargeBackupScreen({required this.sessionTracker, super.key});

  final LargeBackupSessionTracker sessionTracker;

  @override
  State<LargeBackupScreen> createState() => _LargeBackupScreenState();
}

class _LargeBackupScreenState extends State<LargeBackupScreen> {
  late final rive.FileLoader _animationLoader;

  @override
  void initState() {
    super.initState();
    _animationLoader = rive.FileLoader.fromAsset(
      "assets/home_tab.riv",
      riveFactory: rive.Factory.flutter,
    );
  }

  @override
  void dispose() {
    _animationLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return SettingsPageScaffold(
      title: pendingTranslation("Backup mode"),
      padding: const EdgeInsets.fromLTRB(32, 0, 32, Spacing.lg),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.sm,
            Spacing.lg,
            Spacing.lg,
          ),
          child: ButtonComponent(
            key: const ValueKey("start-large-backup-mode"),
            label: pendingTranslation("Start backup mode"),
            shouldSurfaceExecutionStates: false,
            onTap: _startStandby,
          ),
        ),
      ),
      children: [
        const SizedBox(height: 80),
        Center(
          child: SizedBox(
            width: 185,
            height: 205,
            child: rive.RiveWidgetBuilder(
              fileLoader: _animationLoader,
              builder: (context, state) {
                if (state is rive.RiveLoaded) {
                  return rive.RiveWidget(
                    controller: state.controller,
                    fit: rive.Fit.contain,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        const SizedBox(height: Spacing.xl),
        Text(
          pendingTranslation("Finish your backup"),
          textAlign: TextAlign.center,
          style: TextStyles.display2.copyWith(color: colors.textBase),
        ),
        const SizedBox(height: Spacing.lg),
        _InstructionItem(
          text: pendingTranslation(
            "Stay in Ente. Switching apps pauses your backup.",
          ),
        ),
        const SizedBox(height: Spacing.md),
        _InstructionItem(
          text: pendingTranslation(
            "The screen dims to save battery. Tap it anytime to come back.",
          ),
        ),
        const SizedBox(height: Spacing.md),
        _InstructionItem(
          text: pendingTranslation("Plug in your phone. Backups use battery."),
        ),
        const SizedBox(height: Spacing.xxl),
      ],
    );
  }

  Future<void> _startStandby() async {
    if (!widget.sessionTracker.isUploading) {
      await showAlertBottomSheet<void>(
        context,
        title: pendingTranslation("No backup in progress"),
        message: pendingTranslation(
          "Start a backup, then return to backup mode.",
        ),
      );
      return;
    }

    final result = await Navigator.of(context).push<_StandbyResult>(
      MaterialPageRoute<_StandbyResult>(
        builder: (_) =>
            _LargeBackupStandbyScreen(sessionTracker: widget.sessionTracker),
      ),
    );
    if (mounted && result == _StandbyResult.backupEnded) {
      Navigator.of(context).pop();
    }
  }
}

enum _StandbyResult { returnedToInstructions, backupEnded }

class _LargeBackupStandbyScreen extends StatefulWidget {
  const _LargeBackupStandbyScreen({required this.sessionTracker});

  final LargeBackupSessionTracker sessionTracker;

  @override
  State<_LargeBackupStandbyScreen> createState() =>
      _LargeBackupStandbyScreenState();
}

class _LargeBackupStandbyScreenState extends State<_LargeBackupStandbyScreen>
    with WidgetsBindingObserver {
  static final _logger = Logger("LargeBackupStandbyScreen");
  static const _applicationBrightness = 0.15;
  static const _dimmingDelay = Duration(seconds: 3);

  final NumberFormat _countFormatter = NumberFormat();
  Timer? _dimmingTimer;
  bool _isClosing = false;
  bool _isScreenDimmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sessionTracker.addListener(_handleBackupSessionChanged);
    widget.sessionTracker.setStandbyScreenActive(true);
    wakeLockService.updateWakeLock(
      enable: true,
      wakeLockFor: WakeLockFor.largeBackupStandbyScreen,
    );
    if (widget.sessionTracker.isUploading) {
      _scheduleScreenDimming();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _close(_StandbyResult.backupEnded);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (widget.sessionTracker.isUploading) {
          _scheduleScreenDimming();
        } else {
          _close(_StandbyResult.backupEnded);
        }
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _close(_StandbyResult.returnedToInstructions);
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    widget.sessionTracker.removeListener(_handleBackupSessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    if (!_isClosing) {
      _stopScreenEffects();
    }
    widget.sessionTracker.setStandbyScreenActive(false);
    Bus.instance.fire(ForceReloadHomeGalleryEvent("largeBackupStandbyEnded"));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: darkThemeData,
      child: GestureDetector(
        key: const ValueKey("large-backup-standby-screen"),
        behavior: HitTestBehavior.opaque,
        onTap: () => _close(_StandbyResult.returnedToInstructions),
        child: Scaffold(
          backgroundColor: fillBaseLight,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  "assets/backup_mode_moon.svg",
                  width: 32,
                  height: 33,
                ),
                const SizedBox(height: 28),
                ListenableBuilder(
                  listenable: widget.sessionTracker,
                  builder: (context, _) {
                    final completed = widget.sessionTracker.completedCount;
                    final total = widget.sessionTracker.totalCount;
                    final statusText = switch ((completed, total)) {
                      (0, 1) => context.strings.uploadingSingleMemory,
                      (0, > 1) => context.strings.uploadingMultipleMemories(
                        count: _countFormatter.format(total),
                      ),
                      (_, > 0) => context.strings.syncProgress(
                        completed: _countFormatter.format(completed),
                        total: _countFormatter.format(total),
                      ),
                      _ => pendingTranslation("Finding more memories…"),
                    };
                    return Text(
                      statusText,
                      style: TextStyles.large.copyWith(
                        color: specialWhiteLight,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 17),
                Text(
                  pendingTranslation("Tap to wake the screen"),
                  style: TextStyles.body.copyWith(color: textLightestLight),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleBackupSessionChanged() {
    if (!widget.sessionTracker.isUploading) {
      _close(_StandbyResult.backupEnded);
    }
  }

  void _close(_StandbyResult result) {
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    _stopScreenEffects();
    Navigator.of(context).pop(result);
  }

  void _stopScreenEffects() {
    _dimmingTimer?.cancel();
    _dimmingTimer = null;
    _isScreenDimmed = false;
    unawaited(_resetApplicationBrightness());
    wakeLockService.updateWakeLock(
      enable: false,
      wakeLockFor: WakeLockFor.largeBackupStandbyScreen,
    );
  }

  void _scheduleScreenDimming() {
    if (_isScreenDimmed || _dimmingTimer != null || _isClosing) {
      return;
    }
    _dimmingTimer = Timer(
      _dimmingDelay,
      () => unawaited(_dimApplicationBrightness()),
    );
  }

  Future<void> _dimApplicationBrightness() async {
    _dimmingTimer = null;
    if (!_canDimScreen) {
      return;
    }

    try {
      final didDim = await EnteScreenBrightness.setApplicationBrightness(
        _applicationBrightness,
      );
      if (!_canDimScreen) {
        if (didDim) {
          await _resetApplicationBrightness();
        }
        return;
      }
      _isScreenDimmed = didDim;
    } catch (error, stackTrace) {
      _logger.warning(
        "Could not dim application brightness",
        error,
        stackTrace,
      );
    }
  }

  Future<void> _resetApplicationBrightness() async {
    try {
      await EnteScreenBrightness.resetApplicationBrightness();
    } catch (error, stackTrace) {
      _logger.warning(
        "Could not reset application brightness",
        error,
        stackTrace,
      );
    }
  }

  bool get _canDimScreen =>
      mounted &&
      !_isClosing &&
      widget.sessionTracker.isUploading &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
}

class _InstructionItem extends StatelessWidget {
  const _InstructionItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 5,
          height: 20,
          child: Align(
            alignment: Alignment.center,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 4),
            ),
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Text(
            text,
            style: TextStyles.body.copyWith(color: colors.textLight),
          ),
        ),
      ],
    );
  }
}
