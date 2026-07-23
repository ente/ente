import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/services/update_service.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AppUpdateDialog extends StatefulWidget {
  final LatestVersionInfo? latestVersionInfo;

  const AppUpdateDialog(this.latestVersionInfo, {super.key});

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  @override
  Widget build(BuildContext context) {
    final enteTextTheme = getEnteTextTheme(context);
    final List<Widget> changelog = [];
    for (final log in widget.latestVersionInfo!.changelog) {
      changelog.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
          child: Text(
            "- $log",
            style: Theme.of(
              context,
            ).textTheme.bodySmall!.copyWith(fontSize: 14),
          ),
        ),
      );
    }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.latestVersionInfo!.name!,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const Padding(padding: EdgeInsets.all(8)),
        if (changelog.isNotEmpty)
          const Text("Changelog", style: TextStyle(fontSize: 18)),
        if (changelog.isNotEmpty) const Padding(padding: EdgeInsets.all(4)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: changelog,
        ),
        const Padding(padding: EdgeInsets.all(8)),
        SizedBox(
          width: double.infinity,
          height: 64,
          child: OutlinedButton(
            style: Theme.of(context).outlinedButtonTheme.style!.copyWith(
              textStyle: WidgetStateProperty.resolveWith<TextStyle?>((
                Set<WidgetState> states,
              ) {
                return Theme.of(context).textTheme.titleMedium;
              }),
            ),
            onPressed: () => launchUrlString(
              PlatformDetector.isDesktop()
                  ? widget.latestVersionInfo!.release!
                  : widget.latestVersionInfo!.url!,
              mode: LaunchMode.externalApplication,
            ),
            child: Text(context.l10n.downloadUpdate),
          ),
        ),
      ],
    );
    final shouldForceUpdate = UpdateService.instance.shouldForceUpdate(
      widget.latestVersionInfo,
    );
    return PopScope(
      canPop: !shouldForceUpdate,
      child: AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 24,
              color: getEnteColorScheme(context).strokeMuted,
            ),
            const SizedBox(height: 16),
            Text(
              shouldForceUpdate
                  ? context.l10n.criticalUpdateAvailable
                  : context.l10n.updateAvailable,
              style: enteTextTheme.h3Bold,
            ),
          ],
        ),
        content: content,
      ),
    );
  }
}
