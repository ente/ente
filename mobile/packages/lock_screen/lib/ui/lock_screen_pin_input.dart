import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:pinput/pinput.dart";

class LockScreenPinInput extends StatelessWidget {
  const LockScreenPinInput({
    super.key,
    required this.title,
    required this.controller,
    required this.useNativeKeyboard,
    required this.forceErrorState,
    required this.onCompleted,
  });

  final String title;
  final TextEditingController controller;
  final bool useNativeKeyboard;
  final bool forceErrorState;
  final ValueChanged<String> onCompleted;

  @override
  Widget build(BuildContext context) {
    final colorTheme = context.componentColors;
    final pinPutDecoration = PinTheme(
      height: 48,
      width: 48,
      padding: const EdgeInsets.only(top: 6.0),
      decoration: BoxDecoration(
        color: colorTheme.backgroundBase,
        border: Border.all(color: colorTheme.strokeDark, width: 1),
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
            Text(title, style: TextStyles.bodyBold),
            const Padding(padding: EdgeInsets.all(12)),
            Pinput(
              length: 4,
              showCursor: false,
              useNativeKeyboard: useNativeKeyboard,
              controller: controller,
              autofocus: true,
              defaultPinTheme: pinPutDecoration.copyWith(
                textStyle: TextStyles.h2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15.0),
                  border: Border.all(color: colorTheme.strokeDark),
                ),
              ),
              submittedPinTheme: pinPutDecoration.copyWith(
                textStyle: TextStyles.h2.copyWith(color: colorTheme.primary),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15.0),
                  border: Border.all(color: colorTheme.primary),
                ),
              ),
              followingPinTheme: pinPutDecoration.copyWith(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15.0),
                  border: Border.all(color: colorTheme.strokeDark),
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
                  border: Border.all(color: colorTheme.warning),
                ),
              ),
              forceErrorState: forceErrorState,
              obscureText: true,
              obscuringCharacter: '*',
              errorText: '',
              onCompleted: onCompleted,
            ),
          ],
        ),
      ),
    );
  }
}
