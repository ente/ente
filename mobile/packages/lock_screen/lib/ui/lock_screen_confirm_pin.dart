import "dart:io";

import "package:ente_lock_screen/lock_screen_settings.dart";
import "package:ente_lock_screen/ui/custom_pin_keypad.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/theme/colors.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:ente_ui/theme/text_style.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:pinput/pinput.dart";

class LockScreenConfirmPin extends StatefulWidget {
  const LockScreenConfirmPin({super.key, required this.pin});
  final String pin;
  @override
  State<LockScreenConfirmPin> createState() => _LockScreenConfirmPinState();
}

class _LockScreenConfirmPinState extends State<LockScreenConfirmPin> {
  final _confirmPinController = TextEditingController(text: null);
  bool isConfirmPinValid = false;
  bool isPlatformDesktop = false;
  final LockScreenSettings _lockscreenSetting = LockScreenSettings.instance;

  @override
  void initState() {
    super.initState();
    isPlatformDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  @override
  void dispose() {
    super.dispose();
    _confirmPinController.dispose();
  }

  Future<void> _confirmPinMatch() async {
    if (widget.pin == _confirmPinController.text) {
      await _lockscreenSetting.setPin(_confirmPinController.text);

      if (mounted) {
        Navigator.of(context).pop(true);
        Navigator.of(context).pop(true);
      }
      return;
    }
    setState(() {
      isConfirmPinValid = true;
    });
    await HapticFeedback.vibrate();
    await Future.delayed(const Duration(milliseconds: 75));
    if (mounted) {
      _confirmPinController.clear();
      setState(() {
        isConfirmPinValid = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorTheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

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
          : CustomPinKeypad(controller: _confirmPinController),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      body: SingleChildScrollView(child: _getBody(colorTheme, textTheme)),
    );
  }

  Widget _getBody(EnteColorScheme colorTheme, EnteTextTheme textTheme) {
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            Image.asset('assets/lock_screen_icon.png', width: 129, height: 95),
            const SizedBox(height: 24),
            Text(context.strings.reEnterPin, style: textTheme.bodyBold),
            const Padding(padding: EdgeInsets.all(12)),
            Pinput(
              length: 4,
              showCursor: false,
              useNativeKeyboard: isPlatformDesktop,
              autofocus: true,
              controller: _confirmPinController,
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
              errorText: '',
              obscureText: true,
              obscuringCharacter: '*',
              forceErrorState: isConfirmPinValid,
              onCompleted: (value) async {
                await _confirmPinMatch();
              },
            ),
          ],
        ),
      ),
    );
  }
}
