import 'package:flutter/material.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/title_bar_title_widget.dart';

///https://www.figma.com/file/SYtMyLBs5SAOkTbfMMzhqt/ente-Visual-Design?node-id=7309%3A29088&t=ReeZ2Big8xSsemZb-4
class BottomOfTitleBarWidget extends StatelessWidget {
  final TitleBarTitleWidget? title;
  final String? caption;
  final bool showCloseButton;

  const BottomOfTitleBarWidget({
    this.title,
    this.caption,
    this.showCloseButton = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: showCloseButton
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title ?? const SizedBox.shrink(),
                caption != null
                    ? Text(
                        caption!,
                        style: getEnteTextTheme(context).small.copyWith(
                          color: getEnteColorScheme(context).textMuted,
                        ),
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
        if (showCloseButton)
          IconButton(
            icon: Icon(
              Icons.close,
              color: getEnteColorScheme(context).strokeFaint,
            ),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }
}
