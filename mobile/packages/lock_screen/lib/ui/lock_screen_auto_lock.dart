import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/captioned_text_widget.dart';
import 'package:ente_ui/components/divider_widget.dart';
import 'package:ente_ui/components/menu_item_widget.dart';
import 'package:ente_ui/components/separators.dart';
import 'package:ente_ui/components/title_bar_title_widget.dart';
import 'package:ente_ui/components/title_bar_widget.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:flutter/material.dart';

class LockScreenAutoLock extends StatefulWidget {
  const LockScreenAutoLock({super.key});

  @override
  State<LockScreenAutoLock> createState() => _LockScreenAutoLockState();
}

class _LockScreenAutoLockState extends State<LockScreenAutoLock> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        primary: false,
        slivers: <Widget>[
          TitleBarWidget(
            flexibleSpaceTitle: TitleBarTitleWidget(
              title: context.strings.autoLock,
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          child: AutoLockItems(),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }, childCount: 1),
          ),
        ],
      ),
    );
  }
}

class AutoLockItems extends StatefulWidget {
  const AutoLockItems({super.key});

  @override
  State<AutoLockItems> createState() => _AutoLockItemsState();
}

class _AutoLockItemsState extends State<AutoLockItems> {
  final autoLockDurations = LockScreenSettings.instance.autoLockDurations;
  List<Widget> items = [];
  Duration currentAutoLockTime = const Duration(seconds: 5);

  @override
  void initState() {
    for (Duration autoLockDuration in autoLockDurations) {
      if (autoLockDuration.inMilliseconds ==
          LockScreenSettings.instance.getAutoLockTime()) {
        currentAutoLockTime = autoLockDuration;
        break;
      }
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    items.clear();
    for (Duration autoLockDuration in autoLockDurations) {
      items.add(_menuItemForPicker(autoLockDuration));
    }
    items = addSeparators(
      items,
      DividerWidget(
        dividerType: DividerType.menuNoIcon,
        bgColor: getEnteColorScheme(context).fillFaint,
      ),
    );
    return Column(mainAxisSize: MainAxisSize.min, children: items);
  }

  Widget _menuItemForPicker(Duration autoLockTime) {
    return MenuItemWidget(
      key: ValueKey(autoLockTime),
      menuItemColor: getEnteColorScheme(context).fillFaint,
      captionedTextWidget: CaptionedTextWidget(
        title: _formatTime(autoLockTime),
      ),
      trailingIcon: currentAutoLockTime == autoLockTime ? Icons.check : null,
      alignCaptionedTextToLeft: true,
      isTopBorderRadiusRemoved: true,
      isBottomBorderRadiusRemoved: true,
      showOnlyLoadingState: true,
      onTap: () async {
        await LockScreenSettings.instance
            .setAutoLockTime(autoLockTime)
            .then(
              (value) => {
                setState(() {
                  currentAutoLockTime = autoLockTime;
                }),
              },
            );
      },
    );
  }

  String _formatTime(Duration duration) {
    if (duration.inHours != 0) {
      return "${duration.inHours}hr";
    } else if (duration.inMinutes != 0) {
      return "${duration.inMinutes}m";
    } else if (duration.inSeconds != 0) {
      return "${duration.inSeconds}s";
    } else {
      return context.strings.immediately;
    }
  }
}
