import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:package_info_plus/package_info_plus.dart";

/// Widget that displays the app version centered at the bottom
/// with an easter egg for tapping multiple times
class AppVersionWidget extends StatefulWidget {
  const AppVersionWidget({super.key});

  @override
  State<AppVersionWidget> createState() => _AppVersionWidgetState();
}

class _AppVersionWidgetState extends State<AppVersionWidget> {
  static const _kTapThresholdForInspector = 5;
  static const _kConsecutiveTapTimeWindowInMilliseconds = 2000;
  static const _kDummyDelayDurationInMilliseconds = 1500;

  int? _lastTap;
  int _consecutiveTaps = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () async {
        final int now = DateTime.now().millisecondsSinceEpoch;
        if (now - (_lastTap ?? now) <
            _kConsecutiveTapTimeWindowInMilliseconds) {
          _consecutiveTaps++;
          if (_consecutiveTaps == _kTapThresholdForInspector) {
            unawaited(
              showBottomSheetComponent<void>(
                context: context,
                isDismissible: false,
                enableDrag: false,
                builder: (_) => BottomSheetComponent(
                  title: "Starting network inspector...",
                  showCloseButton: false,
                  content: Row(
                    children: [
                      SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Please wait",
                          style: TextStyles.body.copyWith(
                            color: colors.textLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            await Future.delayed(
              const Duration(milliseconds: _kDummyDelayDurationInMilliseconds),
            );
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          }
        } else {
          _consecutiveTaps = 1;
        }
        _lastTap = now;
      },
      child: FutureBuilder<String>(
        future: _getAppVersion(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  "Version ${snapshot.data!}",
                  style: TextStyles.mini.copyWith(color: colors.textLight),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Future<String> _getAppVersion() async {
    final pkgInfo = await PackageInfo.fromPlatform();
    return pkgInfo.version;
  }
}
