import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

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
            PinInputComponent(
              length: 4,
              controller: controller,
              autofocus: true,
              useNativeKeyboard: useNativeKeyboard,
              obscureText: true,
              isError: forceErrorState,
              onCompleted: onCompleted,
            ),
          ],
        ),
      ),
    );
  }
}
