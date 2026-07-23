import 'package:flutter/material.dart';
import "package:flutter_animate/flutter_animate.dart";
import "package:photos/ente_theme_data.dart";
import 'package:photos/theme/colors.dart';
import "package:photos/theme/ente_theme.dart";
import 'package:photos/theme/text_style.dart';
import 'package:photos/ui/components/buttons/icon_button_widget.dart';

// CreateNotificationType enum
enum NotificationType { warning, banner, greenBanner, goldenBanner, notice }

class NotificationWidget extends StatelessWidget {
  final IconData startIcon;
  final IconData? actionIcon;
  final Widget? actionWidget;
  final String text;
  final String? subText;
  final GestureTapCallback onTap;
  final NotificationType type;
  final bool isBlackFriday;
  final TextStyle? mainTextStyle;

  const NotificationWidget({
    super.key,
    required this.startIcon,
    required this.actionIcon,
    required this.text,
    required this.onTap,
    this.mainTextStyle,
    this.isBlackFriday = false,
    this.subText,
    this.actionWidget,
    this.type = NotificationType.warning,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    EnteTextTheme textTheme = getEnteTextTheme(context);
    TextStyle mainTextStyle = this.mainTextStyle ?? darkTextTheme.bodyBold;
    TextStyle subTextStyle = darkTextTheme.miniMuted;
    LinearGradient? backgroundGradient;
    Color? backgroundColor;
    EnteColorScheme strokeColorScheme = darkScheme;
    List<BoxShadow>? boxShadow;
    switch (type) {
      case NotificationType.warning:
        backgroundColor = warning500;
        break;
      case NotificationType.banner:
        textTheme = getEnteTextTheme(context);
        backgroundColor = colorScheme.backgroundElevated2;
        mainTextStyle = textTheme.bodyBold;
        subTextStyle = textTheme.miniMuted;
        strokeColorScheme = colorScheme;
        boxShadow = [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 1),
        ];
        break;
      case NotificationType.goldenBanner:
        backgroundGradient = LinearGradient(
          colors: [colorScheme.golden700, colorScheme.golden500],
          stops: const [0.25, 1],
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
        );
        boxShadow = Theme.of(context).colorScheme.enteTheme.shadowMenu;
        break;
      case NotificationType.greenBanner:
        backgroundGradient = LinearGradient(
          colors: [
            getEnteColorScheme(context).primary700,
            getEnteColorScheme(context).primary500,
          ],
          stops: const [0.25, 1],
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
        );
        boxShadow = Theme.of(context).colorScheme.enteTheme.shadowMenu;
        break;
      case NotificationType.notice:
        backgroundColor = colorScheme.backgroundElevated2;
        mainTextStyle = textTheme.bodyBold;
        subTextStyle = textTheme.miniMuted;
        strokeColorScheme = colorScheme;
        boxShadow = Theme.of(context).colorScheme.enteTheme.shadowMenu;
        break;
    }
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            boxShadow: boxShadow,
            color: backgroundColor,
            gradient: backgroundGradient,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: actionWidget != null ? 12 : 8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                isBlackFriday
                    ? Icon(
                            startIcon,
                            size: 36,
                            color: strokeColorScheme.strokeBase,
                          )
                          .animate(
                            onPlay: (controller) =>
                                controller.repeat(reverse: true),
                            delay: 2000.ms,
                          )
                          .shake(duration: 500.ms, hz: 6, delay: 1600.ms)
                          .scale(
                            duration: 500.ms,
                            begin: const Offset(0.9, 0.9),
                            end: const Offset(1.1, 1.1),
                            delay: 1600.ms,
                            // curve: Curves.easeInOut,
                          )
                    : Icon(
                        startIcon,
                        size: 36,
                        color: strokeColorScheme.strokeBase,
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: mainTextStyle,
                        textAlign: TextAlign.left,
                      ),
                      subText != null
                          ? Text(subText!, style: subTextStyle)
                          : const SizedBox.shrink(),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (actionWidget != null)
                  actionWidget!
                else if (actionIcon != null)
                  IconButtonWidget(
                    icon: actionIcon!,
                    iconButtonType: IconButtonType.rounded,
                    iconColor: strokeColorScheme.strokeBase,
                    defaultColor: strokeColorScheme.fillFaint,
                    pressedColor: strokeColorScheme.fillMuted,
                    onTap: onTap,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationTipWidget extends StatelessWidget {
  final String name;
  const NotificationTipWidget(this.name, {super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.strokeFaint),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(flex: 12, child: Text(name, style: textTheme.miniFaint)),
          Flexible(
            flex: 2,
            child: Icon(
              Icons.tips_and_updates_outlined,
              color: colorScheme.strokeFaint,
              size: 36,
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationNoteWidget extends StatelessWidget {
  final String note;
  const NotificationNoteWidget(this.note, {super.key});
  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.strokeMuted),
        color: colorScheme.backgroundColour,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(Icons.info, color: colorScheme.strokeMuted, size: 36),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Note", style: textTheme.miniFaint),
                const SizedBox(height: 2),
                Text(note, style: textTheme.smallMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
