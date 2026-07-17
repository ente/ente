import 'dart:io';
import 'dart:math';

import 'package:ente_accounts/ente_accounts.dart';
import 'package:ente_lock_screen/auth_util.dart';
import 'package:ente_lock_screen/lock_screen_host.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_lock_screen/ui/app_lock.dart';
import 'package:ente_lock_screen/ui/local_authentication_unavailable_dialog.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:logging/logging.dart';

class LockScreen extends StatefulWidget {
  final LockScreenHost config;

  final String Function(BuildContext context)? authReasonBuilder;

  final Future<void> Function(BuildContext context)? onLogout;

  const LockScreen(
    this.config, {
    this.authReasonBuilder,
    this.onLogout,
    super.key,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  final _logger = Logger("LockScreen");
  bool _isShowingLockScreen = false;
  bool _hasPlacedAppInBackground = false;
  bool _hasAuthenticationFailed = false;
  int? lastAuthenticatingTime;
  bool isTimerRunning = false;
  int lockedTimeInSeconds = 0;
  int invalidAttemptCount = 0;
  int remainingTimeInSeconds = 0;
  final _lockscreenSetting = LockScreenSettings.instance;
  // Suppress auto-auth only for the initial manual presentation.
  bool _suppressAutoPrompt = false;
  // Opening the Linux setup guide can background the app; skip that resume.
  bool _suppressNextLifecyclePrompt = false;

  @override
  void initState() {
    _logger.info("initiatingState");
    super.initState();
    invalidAttemptCount = _lockscreenSetting.getInvalidAttemptCount();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final Map<String, dynamic>? args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      final bool isManualPresentation = args?['manual'] as bool? ?? false;
      _suppressAutoPrompt = isManualPresentation;
      if (!isManualPresentation) {
        _showLockScreen(source: "postFrameInit");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorTheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: widget.config.isLoggedIn()
            ? IconButton(
                icon: const Icon(Icons.logout_outlined),
                color: Theme.of(context).iconTheme.color,
                onPressed: () {
                  _onLogoutTapped(context);
                },
              )
            : const SizedBox.shrink(),
      ),
      body: GestureDetector(
        onTap: () {
          if (isTimerRunning) return;
          _showLockScreen(source: "tap");
        },
        child: Center(
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                height: 120,
                width: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Colors.grey.shade500.withValues(alpha: 0.2),
                            Colors.grey.shade50.withValues(alpha: 0.1),
                            Colors.grey.shade400.withValues(alpha: 0.2),
                            Colors.grey.shade300.withValues(alpha: 0.4),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorTheme.backgroundBase,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 75,
                      width: 75,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: isTimerRunning ? 0 : 1,
                          end: isTimerRunning ? _getFractionOfTimeElapsed() : 1,
                        ),
                        duration: const Duration(seconds: 1),
                        builder: (context, value, _) =>
                            CircularProgressIndicator(
                              backgroundColor: colorTheme.fillFaintPressed,
                              value: value,
                              color: colorTheme.primary400,
                              strokeWidth: 1.5,
                            ),
                      ),
                    ),
                    Icon(Icons.lock, size: 30, color: colorTheme.textBase),
                  ],
                ),
              ),
              const Spacer(),
              isTimerRunning
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                              context.strings.tooManyIncorrectAttempts,
                              style: textTheme.small,
                            )
                            .animate(delay: const Duration(milliseconds: 2000))
                            .fadeOut(
                              duration: 400.ms,
                              curve: Curves.easeInOutCirc,
                            ),
                        Text(
                              _formatTime(remainingTimeInSeconds),
                              style: textTheme.small,
                            )
                            .animate(delay: const Duration(milliseconds: 2250))
                            .fadeIn(
                              duration: 400.ms,
                              curve: Curves.easeInOutCirc,
                            ),
                      ],
                    )
                  : GestureDetector(
                      onTap: () => _showLockScreen(source: "tap"),
                      child: Text(
                        context.strings.tapToUnlock,
                        style: textTheme.small,
                      ),
                    ),
              const Padding(padding: EdgeInsets.only(bottom: 24)),
            ],
          ),
        ),
      ),
    );
  }

  void _onLogoutTapped(BuildContext context) {
    showChoiceActionSheet(
      context,
      title: context.strings.areYouSureYouWantToLogout,
      firstButtonLabel: context.strings.yesLogout,
      isCritical: true,
      firstButtonOnTap: () async {
        if (widget.onLogout != null) {
          await widget.onLogout!(context);
        } else {
          await UserService.instance.logout(context);
        }
        // To start the app afresh, resetting all state.
        Process.killPid(pid, ProcessSignal.sigkill);
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.info(state.toString());
    if (state == AppLifecycleState.resumed && !_isShowingLockScreen) {
      if (_suppressNextLifecyclePrompt) {
        _suppressNextLifecyclePrompt = false;
        _hasPlacedAppInBackground = false;
        return;
      }
      // This is triggered either when the lock screen is dismissed or when
      // the app is brought to foreground
      _hasPlacedAppInBackground = false;
      final bool didAuthInLast5Seconds =
          lastAuthenticatingTime != null &&
          DateTime.now().millisecondsSinceEpoch - lastAuthenticatingTime! <
              5000;
      if (!_hasAuthenticationFailed && !didAuthInLast5Seconds) {
        // If there is a cooldown timer (after multiple failures), respect it
        if (_lockscreenSetting.getlastInvalidAttemptTime() >
                DateTime.now().millisecondsSinceEpoch &&
            !_isShowingLockScreen) {
          final int time =
              (_lockscreenSetting.getlastInvalidAttemptTime() -
                  DateTime.now().millisecondsSinceEpoch) ~/
              1000;
          Future.delayed(Duration.zero, () {
            startLockTimer(time);
            _showLockScreen(source: "lifeCycle");
          });
        } else if (!_suppressAutoPrompt) {
          // No cooldown: auto-prompt when app becomes active again
          _showLockScreen(source: "lifeCycle");
        }
      } else {
        _hasAuthenticationFailed = false; // Reset failure state
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // This is triggered either when the lock screen pops up or when
      // the app is pushed to background
      if (!_isShowingLockScreen) {
        _hasPlacedAppInBackground = true;
        _hasAuthenticationFailed = false; // reset failure state
        // If we suppressed the initial auto-prompt due to manual lock,
        // enable auto-prompt for the next resume after focus loss.
        _suppressAutoPrompt = false;
      }
    }
  }

  @override
  void dispose() {
    _logger.info('disposing');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> startLockTimer(int timeInSeconds) async {
    if (isTimerRunning) {
      return;
    }

    setState(() {
      isTimerRunning = true;
      remainingTimeInSeconds = timeInSeconds;
    });

    while (remainingTimeInSeconds > 0) {
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        remainingTimeInSeconds--;
      });
    }

    setState(() {
      isTimerRunning = false;
    });
  }

  double _getFractionOfTimeElapsed() {
    final int totalLockedTime = lockedTimeInSeconds =
        pow(2, invalidAttemptCount - 5).toInt() * 30;
    if (remainingTimeInSeconds == 0) return 1;

    return 1 - remainingTimeInSeconds / totalLockedTime;
  }

  String _formatTime(int seconds) {
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int remainingSeconds = seconds % 60;

    if (hours > 0) {
      return "${hours}h ${minutes}m";
    } else if (minutes > 0) {
      return "${minutes}m ${remainingSeconds}s";
    } else {
      return "${remainingSeconds}s";
    }
  }

  Future<void> _autoLogoutOnMaxInvalidAttempts() async {
    _logger.info("Auto logout on max invalid attempts");
    Navigator.of(context, rootNavigator: true).pop('dialog');
    Navigator.of(context).popUntil((route) => route.isFirst);
    final dialog = createProgressDialog(context, context.strings.loggingOut);
    await dialog.show();
    await widget.config.logout();
    await dialog.hide();
  }

  Future<void> _showLockScreen({String source = ''}) async {
    final int currentTimestamp = DateTime.now().millisecondsSinceEpoch;
    _logger.info("Showing lock screen $source $currentTimestamp");
    try {
      if (currentTimestamp < _lockscreenSetting.getlastInvalidAttemptTime() &&
          !_isShowingLockScreen) {
        final int remainingTime =
            (_lockscreenSetting.getlastInvalidAttemptTime() -
                currentTimestamp) ~/
            1000;

        await startLockTimer(remainingTime);
        if (!mounted) {
          return;
        }
      }
      _isShowingLockScreen = true;
      final result = isTimerRunning
          ? false
          : await requestAuthentication(
              context,
              widget.authReasonBuilder?.call(context) ??
                  context.strings.authToViewSecrets,
              macOSReason: context.strings.unlock,
              isOpeningApp: true,
            );
      if (!mounted) {
        _isShowingLockScreen = false;
        return;
      }
      _logger.finest("LockScreen Result $result $currentTimestamp");
      _isShowingLockScreen = false;
      if (result) {
        lastAuthenticatingTime = DateTime.now().millisecondsSinceEpoch;
        AppLock.of(context)?.didUnlock();
        await _lockscreenSetting.setInvalidAttemptCount(0);
        setState(() {
          lockedTimeInSeconds = 15;
          isTimerRunning = false;
        });
      } else {
        if (!_hasPlacedAppInBackground) {
          // Treat this as a failure only if user did not explicitly
          // put the app in background
          if (_lockscreenSetting.getInvalidAttemptCount() > 4 &&
              invalidAttemptCount !=
                  _lockscreenSetting.getInvalidAttemptCount()) {
            invalidAttemptCount = _lockscreenSetting.getInvalidAttemptCount();

            // For logged-in users, auto-logout after 10 failed attempts
            if (invalidAttemptCount > 9 && widget.config.isLoggedIn()) {
              await _autoLogoutOnMaxInvalidAttempts();
              return;
            }

            lockedTimeInSeconds = pow(2, invalidAttemptCount - 5).toInt() * 30;
            await _lockscreenSetting.setLastInvalidAttemptTime(
              DateTime.now().millisecondsSinceEpoch +
                  lockedTimeInSeconds * 1000,
            );
            await startLockTimer(lockedTimeInSeconds);
          }
          _hasAuthenticationFailed = true;
          _logger.info("Authentication failed");
        }
      }
    } on WindowsLocalAuthenticationException catch (e, s) {
      _isShowingLockScreen = false;
      _logger.warning("Windows local authentication failed", e, s);
      if (mounted) {
        showToast(context, e.userMessage);
      }
    } on LocalAuthenticationUnavailableException catch (e, s) {
      _isShowingLockScreen = false;
      _logger.warning("System local authentication unavailable", e, s);
      if (mounted) {
        await showLocalAuthenticationUnavailableMessage(
          context,
          e,
          onOpenGuide: () {
            _suppressNextLifecyclePrompt = true;
          },
        );
      }
    } catch (e, s) {
      _isShowingLockScreen = false;
      _logger.severe("Failed to show lock screen", e, s);
    }
  }
}
