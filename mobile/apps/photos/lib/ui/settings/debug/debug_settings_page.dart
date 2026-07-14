import "package:ente_crypto/ente_crypto.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/christmas_banner_event.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/ignored_files_service.dart";
import "package:photos/services/sync/local_sync_service.dart";
import "package:photos/services/sync/sync_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import "package:photos/ui/components/settings/settings_grouped_card.dart";
import "package:photos/ui/components/toggle_switch_widget.dart";
import "package:photos/ui/home/christmas/christmas_utils.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/settings/debug/social_debug_screen.dart";

class DebugSettingsPage extends StatefulWidget {
  const DebugSettingsPage({super.key});

  @override
  State<DebugSettingsPage> createState() => _DebugSettingsPageState();
}

class _DebugSettingsPageState extends State<DebugSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(
                  Icons.arrow_back,
                  color: colorScheme.strokeBase,
                  size: 24,
                ),
              ),
              const SizedBox(height: 24),
              Text("Debug", style: textTheme.h3Bold),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      SettingsGroupedCard(
                        children: [
                          MenuItemWidgetNew(
                            title: "Disable internal user features",
                            leadingIconWidget: _buildIconWidget(
                              context,
                              HugeIcons.strokeRoundedUserBlock01,
                            ),
                            trailingWidget: ToggleSwitchWidget(
                              value: () => localSettings.isInternalUserDisabled,
                              onChanged: () async {
                                final newValue =
                                    !localSettings.isInternalUserDisabled;
                                await localSettings.setInternalUserDisabled(
                                  newValue,
                                );
                                if (!mounted) return;
                                setState(() {});
                                if (!context.mounted) return;
                                showShortToast(
                                  context,
                                  newValue
                                      ? "Internal user disabled. Restart app."
                                      : "Internal user enabled. Restart app.",
                                );
                              },
                            ),
                          ),
                          MenuItemWidgetNew(
                            title: "Use Cloudflare upload proxy",
                            leadingIconWidget: _buildIconWidget(
                              context,
                              HugeIcons.strokeRoundedUpload04,
                            ),
                            trailingWidget: ToggleSwitchWidget(
                              value: () =>
                                  localSettings.cfUploadProxyEnabled ??
                                  flagService.cloudflareUploadWorker,
                              onChanged: () async {
                                final newValue =
                                    !(localSettings.cfUploadProxyEnabled ??
                                        flagService.cloudflareUploadWorker);
                                await localSettings.setCFUploadProxyEnabled(
                                  newValue,
                                );
                                if (!mounted) return;
                                setState(() {});
                                if (!context.mounted) return;
                                showShortToast(
                                  context,
                                  newValue
                                      ? "Cloudflare upload proxy enabled."
                                      : "Cloudflare upload proxy disabled.",
                                );
                              },
                            ),
                          ),
                          if (flagService.flags.internalUser)
                            MenuItemWidgetNew(
                              title: "Background sync notification",
                              leadingIconWidget: _buildIconWidget(
                                context,
                                HugeIcons.strokeRoundedNotification01,
                              ),
                              trailingWidget: ToggleSwitchWidget(
                                value: () =>
                                    localSettings.isBGDebugNotificationsEnabled,
                                onChanged: () async {
                                  final newValue = !localSettings
                                      .isBGDebugNotificationsEnabled;
                                  await localSettings
                                      .setBGDebugNotificationsEnabled(newValue);
                                  if (!mounted) return;
                                  setState(() {});
                                  if (!context.mounted) return;
                                  showShortToast(
                                    context,
                                    newValue
                                        ? "Background debug notifications enabled. Restart app."
                                        : "Background debug notifications disabled. Restart app.",
                                  );
                                },
                              ),
                            ),
                          MenuItemWidgetNew(
                            title: "Enable database logging",
                            leadingIconWidget: _buildIconWidget(
                              context,
                              HugeIcons.strokeRoundedDatabase01,
                            ),
                            trailingWidget: ToggleSwitchWidget(
                              value: () => localSettings.enableDatabaseLogging,
                              onChanged: () async {
                                final newValue =
                                    !localSettings.enableDatabaseLogging;
                                await localSettings.setEnableDatabaseLogging(
                                  newValue,
                                );
                                if (!mounted) return;
                                setState(() {});
                                if (!context.mounted) return;
                                showShortToast(
                                  context,
                                  newValue
                                      ? "Database logging enabled. Restart app."
                                      : "Database logging disabled. Restart app.",
                                );
                              },
                            ),
                          ),
                          MenuItemWidgetNew(
                            title: "Show local ID over thumbnails",
                            leadingIconWidget: _buildIconWidget(
                              context,
                              HugeIcons.strokeRoundedImage01,
                            ),
                            trailingWidget: ToggleSwitchWidget(
                              value: () =>
                                  localSettings.showLocalIDOverThumbnails,
                              onChanged: () async {
                                await localSettings
                                    .setShowLocalIDOverThumbnails(
                                      !localSettings.showLocalIDOverThumbnails,
                                    );
                                if (!mounted) return;
                                setState(() {});
                                if (!context.mounted) return;
                                showShortToast(
                                  context,
                                  localSettings.showLocalIDOverThumbnails
                                      ? "Local IDs will be shown. Restart app."
                                      : "Local IDs hidden. Restart app.",
                                );
                              },
                            ),
                          ),
                          if (isChristmasDateRange())
                            MenuItemWidgetNew(
                              title: "Christmas banner",
                              leadingIconWidget: _buildIconWidget(
                                context,
                                HugeIcons.strokeRoundedSparkles,
                              ),
                              trailingWidget: ToggleSwitchWidget(
                                value: () =>
                                    localSettings.isChristmasBannerEnabled,
                                onChanged: () async {
                                  await localSettings.setChristmasBannerEnabled(
                                    !localSettings.isChristmasBannerEnabled,
                                  );
                                  Bus.instance.fire(ChristmasBannerEvent());
                                  setState(() {});
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SettingsGroupedCard(
                        children: [
                          MenuItemWidgetNew(
                            title: "Key attributes",
                            leadingIconWidget: _buildIconWidget(
                              context,
                              HugeIcons.strokeRoundedKey01,
                            ),
                            trailingIcon: Icons.chevron_right_outlined,
                            trailingIconIsMuted: true,
                            onTap: () async {
                              await updateService.resetChangeLog();
                              if (!context.mounted) return;
                              _showKeyAttributesDialog(context);
                            },
                          ),
                          MenuItemWidgetNew(
                            title: "Delete Local Import DB",
                            leadingIconWidget: _buildIconWidget(
                              context,
                              HugeIcons.strokeRoundedDelete02,
                            ),
                            trailingIcon: Icons.chevron_right_outlined,
                            trailingIconIsMuted: true,
                            onTap: () async {
                              await LocalSyncService.instance.resetLocalSync();
                              if (!context.mounted) return;
                              showShortToast(context, "Done");
                            },
                          ),
                          MenuItemWidgetNew(
                            title: "Allow auto-upload for ignored files",
                            leadingIconWidget: _buildIconWidget(
                              context,
                              HugeIcons.strokeRoundedUpload04,
                            ),
                            trailingIcon: Icons.chevron_right_outlined,
                            trailingIconIsMuted: true,
                            onTap: () async {
                              await IgnoredFilesService.instance.reset();
                              SyncService.instance.sync().ignore();
                              if (!context.mounted) return;
                              showShortToast(context, "Done");
                            },
                          ),
                          MenuItemWidgetNew(
                            title: "Social settings",
                            leadingIconWidget: _buildIconWidget(
                              context,
                              HugeIcons.strokeRoundedShare01,
                            ),
                            trailingIcon: Icons.chevron_right_outlined,
                            trailingIconIsMuted: true,
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const SocialDebugScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconWidget(BuildContext context, List<List<dynamic>> icon) {
    final colorScheme = getEnteColorScheme(context);
    return HugeIcon(
      icon: icon,
      color: colorScheme.menuItemIconStroke,
      size: 20,
    );
  }

  void _showKeyAttributesDialog(BuildContext context) {
    final keyAttributes = Configuration.instance.getKeyAttributes()!;
    final AlertDialog alert = AlertDialog(
      title: const Text("key attributes"),
      content: SingleChildScrollView(
        child: Column(
          children: [
            const Text("Key", style: TextStyle(fontWeight: FontWeight.bold)),
            Text(CryptoUtil.bin2base64(Configuration.instance.getKey()!)),
            const Padding(padding: EdgeInsets.all(12)),
            const Text(
              "Encrypted Key",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(keyAttributes.encryptedKey),
            const Padding(padding: EdgeInsets.all(12)),
            const Text(
              "Key Decryption Nonce",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(keyAttributes.keyDecryptionNonce),
            const Padding(padding: EdgeInsets.all(12)),
            const Text(
              "KEK Salt",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(keyAttributes.kekSalt),
            const Padding(padding: EdgeInsets.all(12)),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text("OK"),
          onPressed: () {
            Navigator.of(context).pop('dialog');
          },
        ),
      ],
    );

    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }
}
