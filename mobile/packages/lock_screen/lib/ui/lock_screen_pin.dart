import "dart:io";

import "package:ente_lock_screen/lock_screen_settings.dart";
import "package:ente_lock_screen/ui/custom_pin_keypad.dart";
import "package:ente_lock_screen/ui/lock_screen_confirm_pin.dart";
import "package:ente_lock_screen/ui/lock_screen_options.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/theme/colors.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:ente_ui/theme/text_style.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import 'package:pinput/pinput.dart';

/// [isChangingLockScreenSettings] Authentication required for changing lock screen settings.
/// Set to true when the app requires the user to authenticate before allowing
/// changes to the lock screen settings.

/// [isAuthenticatingOnAppLaunch] Authentication required on app launch.
/// Set to true when the app requires the user to authenticate immediately upon opening.

/// [isAuthenticatingForInAppChange] Authentication required for in-app changes (e.g., email, password).
/// Set to true when the app requires the to authenticate for sensitive actions like email, password changes.

class LockScreenPin extends StatefulWidget {
  const LockScreenPin({
    super.key,
    this.isChangingLockScreenSettings = false,
    this.isAuthenticatingOnAppLaunch = false,
    this.isAuthenticatingForInAppChange = false,
    this.authPin,
  });

  final bool isAuthenticatingOnAppLaunch;
  final bool isChangingLockScreenSettings;
  final bool isAuthenticatingForInAppChange;
  final String? authPin;
  @override
  State<LockScreenPin> createState() => _LockScreenPinState();
}

class _LockScreenPinState extends State<LockScreenPin> {
  final _pinController = TextEditingController(text: null);

  final LockScreenSettings _lockscreenSetting = LockScreenSettings.instance;
  bool isPinValid = false;
  int invalidAttemptsCount = 0;
  bool isPlatformDesktop = false;

  @override
  void initState() {
    super.initState();
    isPlatformDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    invalidAttemptsCount = _lockscreenSetting.getInvalidAttemptCount();
  }

  @override
  void dispose() {
    super.dispose();
    _pinController.dispose();
  }

  Future<bool> confirmPinAuth(String inputtedPin) async {
    final matched = _lockscreenSetting.useLegacyHashFallback
        ? await _lockscreenSetting.verifyWithLegacyFallback(
            text: inputtedPin,
            storedHash: widget.authPin,
            storageKey: LockScreenSettings.pin,
          )
        : await _lockscreenSetting.verify(
            text: inputtedPin,
            storedHash: widget.authPin,
          );
    if (matched) {
      invalidAttemptsCount = 0;
      await _lockscreenSetting.setInvalidAttemptCount(0);
      if (mounted) {
        widget.isAuthenticatingOnAppLaunch ||
                widget.isAuthenticatingForInAppChange
            ? Navigator.of(context).pop(true)
            : Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => const LockScreenOptions(),
                ),
              );
      }
      return true;
    } else {
      if (mounted) {
        setState(() {
          isPinValid = true;
        });
      }
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 75));
      if (mounted) {
        _pinController.clear();
        setState(() {
          isPinValid = false;
        });
      }

      if (widget.isAuthenticatingOnAppLaunch) {
        invalidAttemptsCount++;
        await _lockscreenSetting.setInvalidAttemptCount(invalidAttemptsCount);
        if (invalidAttemptsCount > 4 && mounted) {
          Navigator.of(context).pop(false);
        }
      }
      return false;
    }
  }

  Future<void> _confirmPin(String inputtedPin) async {
    if (widget.isChangingLockScreenSettings) {
      await confirmPinAuth(inputtedPin);
      return;
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) =>
              LockScreenConfirmPin(pin: inputtedPin),
        ),
      );
      if (mounted) {
        _pinController.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorTheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    final pinPutDecoration = PinTheme(
      height: 48,
      width: 48,
      padding: const EdgeInsets.only(top: 6.0),
      decoration: BoxDecoration(
        color: colorTheme.backgroundBase,
        border: Border.all(color: colorTheme.fillMuted, width: 1),
        borderRadius: BorderRadius.circular(15.0),
      ),
    );
    return Scaffold(
      backgroundColor: colorTheme.backgroundBase,
      appBar: AppBar(
        backgroundColor: colorTheme.backgroundBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () {
            Navigator.of(context).pop(false);
          },
          icon: Icon(Icons.arrow_back, color: colorTheme.textBase),
        ),
        centerTitle: true,
        title: SvgPicture.asset(
          LockScreenSettings.instance.appLogoAsset,
          height: LockScreenSettings.instance.appLogoHeight,
          colorFilter: ColorFilter.mode(colorTheme.primary700, BlendMode.srcIn),
        ),
      ),
      floatingActionButton: isPlatformDesktop
          ? null
          : CustomPinKeypad(controller: _pinController),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      body: SingleChildScrollView(
        child: _getBody(colorTheme, textTheme, pinPutDecoration),
      ),
    );
  }

  Widget _getBody(
    EnteColorScheme colorTheme,
    EnteTextTheme textTheme,
    PinTheme pinPutDecoration,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            Image.asset('assets/lock_screen_icon.png', width: 129, height: 95),
            const SizedBox(height: 24),
            Text(
              widget.isChangingLockScreenSettings
                  ? context.strings.enterAppLockPin
                  : context.strings.setNewPin,
              style: textTheme.bodyBold,
            ),
            const Padding(padding: EdgeInsets.all(12)),
            Pinput(
              length: 4,
              showCursor: false,
              useNativeKeyboard: isPlatformDesktop,
              controller: _pinController,
              autofocus: true,
              defaultPinTheme: pinPutDecoration.copyWith(
                textStyle: textTheme.h3Bold,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15.0),
                  border: Border.all(color: colorTheme.fillMuted),
                ),
              ),
              submittedPinTheme: pinPutDecoration.copyWith(
                textStyle: textTheme.h3Bold.copyWith(
                  color: colorTheme.primary700,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15.0),
                  border: Border.all(color: colorTheme.primary700),
                ),
              ),
              followingPinTheme: pinPutDecoration.copyWith(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15.0),
                  border: Border.all(color: colorTheme.fillMuted),
                ),
              ),
              focusedPinTheme: pinPutDecoration.copyWith(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15.0),
                  border: Border.all(color: colorTheme.fillBase),
                ),
              ),
              errorPinTheme: pinPutDecoration.copyWith(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15.0),
                  border: Border.all(color: colorTheme.warning400),
                ),
              ),
              forceErrorState: isPinValid,
              obscureText: true,
              obscuringCharacter: '*',
              errorText: '',
              onCompleted: (value) async {
                await _confirmPin(_pinController.text);
              },
            ),
          ],
        ),
      ),
    );
  }
}
