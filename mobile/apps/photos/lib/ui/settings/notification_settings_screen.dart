import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/notification_service.dart";
import "package:photos/ui/settings/components/settings_item.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _hasPermission = false, _isCompletingToggle = false;
  Future<void> Function()? _pendingToggle;
  Timer? _permissionTimer;

  @override
  void initState() {
    super.initState();
    _refreshNotificationPermission();
  }

  @override
  void dispose() {
    _permissionTimer?.cancel();
    super.dispose();
  }

  Future<bool> _refreshNotificationPermission() async {
    final granted = await NotificationService.instance.hasGrantedPermissions();
    if (mounted && _hasPermission != granted) {
      setState(() => _hasPermission = granted);
    }
    return granted;
  }

  Future<void> _runWithPermission(Future<void> Function() toggle) async {
    if (_hasPermission) return toggle();

    _pendingToggle = toggle;
    _permissionTimer ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _completePendingToggle(),
    );
    await NotificationService.instance.requestPermissions();
    await _completePendingToggle();
  }

  Future<void> _completePendingToggle() async {
    if (_isCompletingToggle) return;
    _isCompletingToggle = true;

    try {
      final toggle = _pendingToggle;
      if (!(await _refreshNotificationPermission()) || toggle == null) return;

      _pendingToggle = null;
      _permissionTimer?.cancel();
      _permissionTimer = null;
      await toggle();
      if (mounted) setState(() {});
    } finally {
      _isCompletingToggle = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final service = NotificationService.instance;
    final showOnlyOnThisDay = isLocalGalleryMode;

    return SettingsPageScaffold(
      title: l10n.notifications,
      children: [
        if (!showOnlyOnThisDay) ...[
          SettingsItem(
            title: l10n.sharedPhotoNotifications,
            subtitle: l10n.sharedPhotoNotificationsExplanation,
            subtitleMaxLines: 2,
            showChevron: false,
            trailing: ToggleSwitchComponent.async(
              value: () =>
                  _hasPermission &&
                  service.shouldShowNotificationsForSharedPhotosAndAlbums(),
              onChanged: () => _runWithPermission(
                () =>
                    service.setShouldShowNotificationsForSharedPhotosAndAlbums(
                      !service
                          .shouldShowNotificationsForSharedPhotosAndAlbums(),
                    ),
              ),
              showStateIcon: false,
            ),
          ),
          const SizedBox(height: 8),
          SettingsItem(
            title: l10n.socialNotifications,
            subtitle: l10n.socialNotificationsExplanation,
            subtitleMaxLines: 2,
            showChevron: false,
            trailing: ToggleSwitchComponent.async(
              value: () =>
                  _hasPermission && service.shouldShowSocialNotifications(),
              onChanged: () => _runWithPermission(
                () => service.setShouldShowSocialNotifications(
                  !service.shouldShowSocialNotifications(),
                ),
              ),
              showStateIcon: false,
            ),
          ),
          const SizedBox(height: 8),
        ],
        SettingsItem(
          title: l10n.onThisDayMemories,
          subtitle: l10n.onThisDayNotificationExplanation,
          subtitleMaxLines: 2,
          showChevron: false,
          trailing: ToggleSwitchComponent.async(
            value: () =>
                _hasPermission && localSettings.isOnThisDayNotificationsEnabled,
            onChanged: () => _runWithPermission(
              memoriesCacheService.toggleOnThisDayNotifications,
            ),
            showStateIcon: false,
          ),
        ),
        if (!showOnlyOnThisDay) ...[
          const SizedBox(height: 8),
          SettingsItem(
            title: l10n.birthdays,
            subtitle: l10n.receiveRemindersOnBirthdays,
            subtitleMaxLines: 2,
            showChevron: false,
            trailing: ToggleSwitchComponent.async(
              value: () =>
                  _hasPermission && localSettings.birthdayNotificationsEnabled,
              onChanged: () => _runWithPermission(
                memoriesCacheService.toggleBirthdayNotifications,
              ),
              showStateIcon: false,
            ),
          ),
        ],
      ],
    );
  }
}
