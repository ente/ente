import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import 'package:photos/services/update_service.dart';
import 'package:photos/theme/ente_theme.dart';
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
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
    final List<Widget> changelog = [];
    final enteTextTheme = getEnteTextTheme(context);
    final enteColor = getEnteColorScheme(context);
    for (final log in widget.latestVersionInfo!.changelog) {
      changelog.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "- ",
                style: enteTextTheme.small.copyWith(color: enteColor.textMuted),
              ),
              Flexible(
                child: Text(
                  log,
                  softWrap: true,
                  style: enteTextTheme.small.copyWith(
                    color: enteColor.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context).aNewVersionOfEnteIsAvailable,
          style: enteTextTheme.body.copyWith(color: enteColor.textMuted),
        ),
        const Padding(padding: EdgeInsets.all(8)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: changelog,
        ),
        const Padding(padding: EdgeInsets.all(8)),
        ButtonWidget(
          buttonType: ButtonType.primary,
          labelText: AppLocalizations.of(context).download,
          onTap: () async {
            // ignore: unawaited_futures
            launchUrlString(
              widget.latestVersionInfo!.url,
              mode: LaunchMode.externalApplication,
            );
          },
        ),
        const SizedBox(height: 6),
        ButtonWidget(
          buttonType: ButtonType.secondary,
          labelText: AppLocalizations.of(context).cancel,
          onTap: () async {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
    final shouldForceUpdate = updateService.shouldForceUpdate(
      widget.latestVersionInfo!,
    );
    return PopScope(
      canPop: !shouldForceUpdate,
      child: AlertDialog(
        key: const ValueKey("updateAppDialog"),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 48,
              color: enteColor.strokeMuted,
            ),
            const SizedBox(height: 16),
            Text(
              shouldForceUpdate
                  ? AppLocalizations.of(context).criticalUpdateAvailable
                  : AppLocalizations.of(context).updateAvailable,
              style: enteTextTheme.h3Bold,
            ),
          ],
        ),
        content: content,
      ),
    );
  }
}
