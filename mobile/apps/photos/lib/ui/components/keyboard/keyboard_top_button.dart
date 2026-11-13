import "package:ente_strings/ente_strings.dart";
import 'package:flutter/cupertino.dart';
import "package:photos/theme/effects.dart";
import 'package:photos/theme/ente_theme.dart';

class KeyboardTopButton extends StatelessWidget {
  final VoidCallback? onDoneTap;
  final VoidCallback? onCancelTap;
  final String? doneText;
  final String? cancelText;

  const KeyboardTopButton({
    super.key,
    this.doneText,
    this.cancelText,
    this.onDoneTap,
    this.onCancelTap,
  });

  @override
  Widget build(BuildContext context) {
    final enteTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        boxShadow: shadowFloatFaintLight,
        color: colorScheme.backgroundElevated2,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              onPressed: onCancelTap,
              child: Text(
                cancelText ?? context.strings.cancel,
                style: enteTheme.smallBold,
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              onPressed: onDoneTap,
              child: Text(
                doneText ?? context.strings.done,
                style: enteTheme.smallBold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
