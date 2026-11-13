import "dart:async";
import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:ente_lock_screen/local_authentication_service.dart";
import "package:ente_lock_screen/lock_screen_settings.dart";
import "package:ente_lock_screen/ui/app_lock.dart";
import "package:ente_lock_screen/ui/local_authentication_unavailable_dialog.dart";
import "package:ente_lock_screen/ui/lock_screen_auto_lock.dart";
import "package:ente_lock_screen/ui/lock_screen_password.dart";
import "package:ente_lock_screen/ui/lock_screen_pin.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";

class LockScreenOptions extends StatefulWidget {
  const LockScreenOptions({super.key});

  @override
  State<LockScreenOptions> createState() => _LockScreenOptionsState();
}

class _LockScreenOptionsState extends State<LockScreenOptions> {
  final LockScreenSettings _lockScreenSettings = LockScreenSettings.instance;
  late bool appLock = false;
  bool isPinEnabled = false;
  bool isPasswordEnabled = false;
  late int autoLockTimeInMilliseconds;
  late bool hideAppContent;
  late bool isSystemLockEnabled = false;

  @override
  void initState() {
    super.initState();
    hideAppContent = _lockScreenSettings.getShouldHideAppContent();
    autoLockTimeInMilliseconds = _lockScreenSettings.getAutoLockTime();
    _initializeSettings();
    appLock = _lockScreenSettings.getIsAppLockSet();
  }

  Future<void> _initializeSettings() async {
    final bool passwordEnabled = await _lockScreenSettings.isPasswordSet();
    final bool pinEnabled = await _lockScreenSettings.isPinSet();
    final bool shouldHideAppContent = _lockScreenSettings
        .getShouldHideAppContent();
    final bool systemLockEnabled = _lockScreenSettings
        .shouldShowSystemLockScreen();
    if (!mounted) {
      return;
    }
    setState(() {
      isPasswordEnabled = passwordEnabled;
      isPinEnabled = pinEnabled;
      hideAppContent = shouldHideAppContent;
      isSystemLockEnabled = systemLockEnabled;
    });
  }

  Future<void> _deviceLock() async {
    if (await LocalAuthenticationService.instance
        .isLocalAuthSupportedOnDevice()) {
      await _lockScreenSettings.removePinAndPassword();
      await _lockScreenSettings.setSystemLockScreen(true);
    } else {
      final linuxStatus = await LocalAuthenticationService.instance
          .getLinuxLocalAuthSetupStatus();
      if (Platform.isLinux && linuxStatus?.setupRequired == true) {
        if (mounted) {
          await showLinuxSystemAuthSetupDialog(context);
        }
        await _initializeSettings();
        return;
      }
      if (mounted) {
        await showBottomSheetComponent(
          context: context,
          builder: (_) => BottomSheetComponent(
            title: context.strings.noSystemLockFound,
            message: context.strings.deviceLockEnablePreSteps,
          ),
        );
      }
    }
    await _initializeSettings();
  }

  Future<void> _pinLock() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return const LockScreenPin();
        },
      ),
    );

    if (result == true) {
      await _lockScreenSettings.setSystemLockScreen(false);
      await _lockScreenSettings.setAppLockEnabled(true);
      setState(() {
        appLock = _lockScreenSettings.getIsAppLockSet();
      });
    }
    await _initializeSettings();
  }

  Future<void> _passwordLock() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return const LockScreenPassword();
        },
      ),
    );
    if (result == true) {
      await _lockScreenSettings.setSystemLockScreen(false);
      await _lockScreenSettings.setAppLockEnabled(true);
      setState(() {
        appLock = _lockScreenSettings.getIsAppLockSet();
      });
    }
    await _initializeSettings();
  }

  Future<void> _onToggleSwitch() async {
    AppLock.of(context)!.setEnabled(!appLock);
    if (await LocalAuthenticationService.instance
        .isLocalAuthSupportedOnDevice()) {
      await _lockScreenSettings.setSystemLockScreen(!appLock);
      await _lockScreenSettings.setAppLockEnabled(!appLock);
    } else {
      await _lockScreenSettings.setSystemLockScreen(false);
      await _lockScreenSettings.setAppLockEnabled(false);
    }
    await _lockScreenSettings.removePinAndPassword();
    await _initializeSettings();
    setState(() {
      appLock = !appLock;
    });
  }

  Future<void> _onAutoLock() async {
    await routeToPage(context, const LockScreenAutoLock()).then((value) {
      setState(() {
        autoLockTimeInMilliseconds = _lockScreenSettings.getAutoLockTime();
      });
    });
  }

  Future<void> _onHideContent() async {
    setState(() {
      hideAppContent = !hideAppContent;
    });
    await _lockScreenSettings.setHideAppContent(hideAppContent);
  }

  String _formatTime(Duration duration) {
    if (duration.inHours != 0) {
      return "in ${duration.inHours} hour${duration.inHours > 1 ? 's' : ''}";
    } else if (duration.inMinutes != 0) {
      return "in ${duration.inMinutes} minute${duration.inMinutes > 1 ? 's' : ''}";
    } else if (duration.inSeconds != 0) {
      return "in ${duration.inSeconds} second${duration.inSeconds > 1 ? 's' : ''}";
    } else {
      return context.strings.immediately;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final descriptionStyle = TextStyles.mini.copyWith(
      color: colors.textLighter,
    );
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: AppBarComponent(
            title: context.strings.appLock,
            slivers: <Widget>[
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MenuComponent(
                                title: context.strings.appLock,
                                trailing: ToggleSwitchComponent.async(
                                  value: () => appLock,
                                  onChanged: () => _onToggleSwitch(),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 210),
                                switchInCurve: Curves.easeOut,
                                switchOutCurve: Curves.easeIn,
                                child: !appLock
                                    ? Padding(
                                        padding: const EdgeInsets.only(
                                          top: 14,
                                          left: 14,
                                          right: 12,
                                        ),
                                        child: Text(
                                          context.strings.appLockDescription,
                                          style: descriptionStyle,
                                          textAlign: TextAlign.left,
                                        ),
                                      )
                                    : const SizedBox(),
                              ),
                              const Padding(padding: EdgeInsets.only(top: 24)),
                            ],
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 210),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            child: appLock
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      MenuGroupComponent(
                                        showDividers: true,
                                        items: [
                                          MenuComponent(
                                            title: context.strings.deviceLock,
                                            trailing: isSystemLockEnabled
                                                ? Icon(
                                                    Icons.check,
                                                    color: colors.textBase,
                                                  )
                                                : null,
                                            onTap: () => _deviceLock(),
                                          ),
                                          MenuComponent(
                                            title: context.strings.pinLock,
                                            trailing: isPinEnabled
                                                ? Icon(
                                                    Icons.check,
                                                    color: colors.textBase,
                                                  )
                                                : null,
                                            onTap: () => _pinLock(),
                                          ),
                                          MenuComponent(
                                            title: context.strings.password,
                                            trailing: isPasswordEnabled
                                                ? Icon(
                                                    Icons.check,
                                                    color: colors.textBase,
                                                  )
                                                : null,
                                            onTap: () => _passwordLock(),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 24),
                                      PlatformDetector.isMobile()
                                          ? MenuComponent(
                                              title: context.strings.autoLock,
                                              subtitle: _formatTime(
                                                Duration(
                                                  milliseconds:
                                                      autoLockTimeInMilliseconds,
                                                ),
                                              ),
                                              onTap: () => _onAutoLock(),
                                            )
                                          : const SizedBox.shrink(),
                                      PlatformDetector.isMobile()
                                          ? Padding(
                                              padding: const EdgeInsets.only(
                                                top: 14,
                                                left: 14,
                                                right: 12,
                                              ),
                                              child: Text(
                                                context
                                                    .strings
                                                    .autoLockFeatureDescription,
                                                style: descriptionStyle,
                                                textAlign: TextAlign.left,
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                          PlatformDetector.isMobile()
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(height: appLock ? 24 : 8),
                                    MenuComponent(
                                      title: context.strings.hideContent,
                                      trailing: ToggleSwitchComponent.async(
                                        value: () => hideAppContent,
                                        onChanged: () => _onHideContent(),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 14,
                                        left: 14,
                                        right: 12,
                                      ),
                                      child: Text(
                                        Platform.isAndroid
                                            ? context
                                                  .strings
                                                  .hideContentDescriptionAndroid
                                            : context
                                                  .strings
                                                  .hideContentDescriptioniOS,
                                        style: descriptionStyle,
                                        textAlign: TextAlign.left,
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  );
                }, childCount: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
