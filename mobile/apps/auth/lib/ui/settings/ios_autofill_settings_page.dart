import 'package:ente_auth/services/ios_autofill_service.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';

class IOSAutoFillSettingsPage extends StatelessWidget {
  const IOSAutoFillSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = IOSAutoFillService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => AuthSettingsPageScaffold(
        title: pendingTranslation('Verification code AutoFill'),
        children: [
          SettingsItem(
            title: pendingTranslation('Enable AutoFill'),
            showChevron: false,
            trailing: ToggleSwitchComponent.async(
              value: () => service.isEnabled,
              onChanged: () async {
                try {
                  if (service.isEnabled) {
                    await service.disable();
                  } else {
                    await service.enable();
                  }
                } catch (_) {
                  if (context.mounted) {
                    showToast(
                      context,
                      pendingTranslation(
                        'Could not update AutoFill. Please try again.',
                      ),
                    );
                  }
                }
              },
            ),
          ),
          const SizedBox(height: Spacing.lg),
          if (service.hasPendingCleanup) ...[
            Text(
              pendingTranslation(
                'AutoFill cleanup could not be confirmed. Retry to remove shared data.',
              ),
            ),
            SettingsItem(
              title: pendingTranslation('Retry AutoFill cleanup'),
              onTap: () async {
                try {
                  await service.retryCleanup();
                } catch (_) {
                  if (context.mounted) {
                    showToast(
                      context,
                      pendingTranslation(
                        'AutoFill cleanup is still pending. Please try again.',
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: Spacing.lg),
          ],
          if (service.unavailableEntries > 0) ...[
            Text(
              pendingTranslation(
                '${service.unavailableEntries} entries could not be made available to AutoFill. Check their secrets and OTP settings.',
              ),
            ),
            const SizedBox(height: Spacing.lg),
          ],
          Text(
            pendingTranslation(
              'Fill TOTP verification codes in Safari and compatible apps without opening Ente Auth. '
              'An encrypted copy of your TOTP secrets is stored on this device for AutoFill. '
              'Face ID, Touch ID or your device passcode is required each time you open the picker. '
              'HOTP and Steam codes are not included.',
            ),
          ),
          if (service.isEnabled) ...[
            const SizedBox(height: Spacing.lg),
            SettingsItem(
              title: pendingTranslation('Open AutoFill settings'),
              onTap: () async {
                try {
                  await service.openSettings();
                } catch (_) {
                  if (context.mounted) {
                    showToast(
                      context,
                      pendingTranslation(
                        'Open Settings → General → AutoFill & Passwords and enable Ente Auth.',
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              pendingTranslation(
                'Enable Ente Auth in Settings → General → AutoFill & Passwords. '
                'Then choose Ente Auth from the AutoFill options in a verification code field and search for your account. '
                'Open Ente Auth to refresh codes changed on another device. Signing out disables AutoFill.',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
