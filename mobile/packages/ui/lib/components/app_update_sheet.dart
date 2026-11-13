import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:url_launcher/url_launcher_string.dart";

Future<void> showAppUpdateSheet(
  BuildContext context, {
  required String version,
  required String downloadUrl,
  required String changelogUrl,
  required bool isCritical,
  required bool notificationsEnabled,
  required Future<void> Function(bool) onNotificationsChanged,
  bool useRootNavigator = false,
}) {
  return showBottomSheetComponent<void>(
    context: context,
    isDismissible: !isCritical,
    enableDrag: !isCritical,
    useRootNavigator: useRootNavigator,
    builder: (_) => _AppUpdateSheet(
      version: version,
      downloadUrl: downloadUrl,
      changelogUrl: changelogUrl,
      isCritical: isCritical,
      notificationsEnabled: notificationsEnabled,
      onNotificationsChanged: onNotificationsChanged,
    ),
  );
}

class _AppUpdateSheet extends StatefulWidget {
  const _AppUpdateSheet({
    required this.version,
    required this.downloadUrl,
    required this.changelogUrl,
    required this.isCritical,
    required this.notificationsEnabled,
    required this.onNotificationsChanged,
  });

  final String version;
  final String downloadUrl;
  final String changelogUrl;
  final bool isCritical;
  final bool notificationsEnabled;
  final Future<void> Function(bool) onNotificationsChanged;

  @override
  State<_AppUpdateSheet> createState() => _AppUpdateSheetState();
}

class _AppUpdateSheetState extends State<_AppUpdateSheet> {
  late bool _notificationsEnabled = widget.notificationsEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    return BottomSheetComponent(
      title: widget.isCritical
          ? l10n.criticalUpdateAvailable
          : l10n.updateAvailable,
      illustration: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: colors.primaryLight,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Center(
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedSparkles,
            size: IconSizes.medium,
            color: colors.primary,
          ),
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.version,
            textAlign: TextAlign.center,
            style: TextStyles.body.copyWith(color: colors.textLight),
          ),
          const SizedBox(height: Spacing.lg),
          Align(
            child: ButtonComponent(
              label: l10n.whatsNew,
              variant: ButtonComponentVariant.secondary,
              size: ButtonComponentSize.small,
              density: ButtonComponentDensity.compact,
              shouldSurfaceExecutionStates: false,
              leading: HugeIcon(
                icon: HugeIcons.strokeRoundedArrowUpRight01,
                size: IconSizes.small,
                color: colors.textBase,
              ),
              onTap: () async {
                await launchUrlString(
                  widget.changelogUrl,
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ),
          if (!widget.isCritical) ...[
            const SizedBox(height: Spacing.xxl),
            Divider(height: 1, thickness: 1, color: colors.strokeFaint),
            const SizedBox(height: Spacing.lg),
            Semantics(
              toggled: _notificationsEnabled,
              label: l10n.notifyMe,
              onTap: () => _setNotificationsEnabled(!_notificationsEnabled),
              excludeSemantics: true,
              child: InkWell(
                onTap: () => _setNotificationsEnabled(!_notificationsEnabled),
                borderRadius: BorderRadius.circular(Radii.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  child: Row(
                    children: [
                      Text(
                        l10n.notifyMe,
                        style: TextStyles.body.copyWith(color: colors.textBase),
                      ),
                      const Spacer(),
                      ToggleSwitchComponent(
                        selected: _notificationsEnabled,
                        onChanged: _setNotificationsEnabled,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      showCloseButton: !widget.isCritical,
      actions: [
        ButtonComponent(
          label: l10n.downloadApplicationUpdate,
          shouldSurfaceExecutionStates: false,
          onTap: () async {
            await launchUrlString(
              widget.downloadUrl,
              mode: LaunchMode.externalApplication,
            );
          },
        ),
      ],
    );
  }

  void _setNotificationsEnabled(bool enabled) {
    setState(() => _notificationsEnabled = enabled);
    widget.onNotificationsChanged(enabled).ignore();
  }
}
