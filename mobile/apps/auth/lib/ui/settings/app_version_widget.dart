import 'package:ente_auth/utils/dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionWidget extends StatefulWidget {
  const AppVersionWidget({super.key});

  @override
  State<AppVersionWidget> createState() => _AppVersionWidgetState();
}

class _AppVersionWidgetState extends State<AppVersionWidget> {
  static const kTapThresholdForInspector = 5;
  static const kConsecutiveTapTimeWindowInMilliseconds = 2000;
  static const kDummyDelayDurationInMilliseconds = 1500;

  int? _lastTap;
  int _consecutiveTaps = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () async {
        final int now = DateTime.now().millisecondsSinceEpoch;
        if (now - (_lastTap ?? now) < kConsecutiveTapTimeWindowInMilliseconds) {
          _consecutiveTaps++;
          if (_consecutiveTaps == kTapThresholdForInspector) {
            final dialog = createProgressDialog(
              context,
              "Starting network inspector...",
            );
            await dialog.show();
            await Future.delayed(
              const Duration(milliseconds: kDummyDelayDurationInMilliseconds),
            );
            await dialog.hide();
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
            return SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Semantics(
                  identifier: 'auth_settings_app_version',
                  child: Center(
                    child: Text(
                      "Version: ${snapshot.data!}",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            );
          }
          return Container();
        },
      ),
    );
  }

  Future<String> _getAppVersion() async {
    final pkgInfo = await PackageInfo.fromPlatform();
    return pkgInfo.version;
  }
}
