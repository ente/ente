import 'package:ente_components/ente_components.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_strings/ente_strings.dart';
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
      backgroundColor: context.componentColors.backgroundBase,
      body: AppBarComponent(
        title: context.strings.autoLock,
        slivers: [
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: AutoLockItems(),
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
    final colors = context.componentColors;
    return MenuGroupComponent(
      showDividers: true,
      items: [
        for (final autoLockDuration in autoLockDurations)
          MenuComponent(
            key: ValueKey(autoLockDuration),
            title: _formatTime(autoLockDuration),
            trailing: currentAutoLockTime == autoLockDuration
                ? Icon(Icons.check, color: colors.textBase)
                : null,
            showOnlyLoadingState: true,
            onTap: () async {
              await LockScreenSettings.instance
                  .setAutoLockTime(autoLockDuration)
                  .then(
                    (value) => setState(() {
                      currentAutoLockTime = autoLockDuration;
                    }),
                  );
            },
          ),
      ],
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
