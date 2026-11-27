import 'dart:async';
import 'dart:io';

import 'package:ente_auth/models/watch/state.dart';
import 'package:ente_auth/services/watch/service.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WatchSettingsPage extends StatefulWidget {
  const WatchSettingsPage({super.key});

  @override
  State<WatchSettingsPage> createState() => _WatchSettingsPageState();
}

enum _WatchAction { approve, disable, refresh }

class _WatchSettingsPageState extends State<WatchSettingsPage> {
  final service = WatchService.instance;
  _WatchAction? activeAction;
  bool get busy => activeAction != null;

  @override
  void initState() {
    super.initState();
    unawaited(service.refresh());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) {
      final state = service.state;
      final colors = context.componentColors;
      final warningColor = Theme.of(context).brightness == Brightness.light
          ? colors.warningDarker
          : colors.warning;
      final canRefresh = switch (state.phase) {
        WatchPhase.unavailable => service.isPlatformSupported,
        WatchPhase.failed || WatchPhase.ambiguous => true,
        _ => false,
      };
      final statusText = switch (state.phase) {
        WatchPhase.unavailable =>
          Platform.isIOS
              ? pendingTranslation(
                  "Needs iOS 17, watchOS 10 and Ente Auth on your Apple Watch.",
                )
              : pendingTranslation(
                  "Needs Android 8, Wear OS 3 and Ente Auth from Google Play on both devices.",
                ),
        WatchPhase.setup ||
        WatchPhase.retiring ||
        WatchPhase.disabled => pendingTranslation(
          "Open Ente Auth on your watch and tap Set up watch.",
        ),
        WatchPhase.approval => pendingTranslation(
          "Your watch will keep a copy of all your codes for offline use.",
        ),
        WatchPhase.pending || WatchPhase.synced => pendingTranslation(
          "Your codes are shared with this watch.",
        ),
        WatchPhase.failed => pendingTranslation(
          "Couldn't update your watch. Open Ente Auth on both devices and try again.",
        ),
        WatchPhase.replacement => pendingTranslation(
          "Another watch wants your codes. Stop sharing with this watch first.",
        ),
        WatchPhase.ambiguous => pendingTranslation(
          "More than one watch is asking. Keep only one nearby and try again.",
        ),
      };
      return AuthSettingsPageScaffold(
        title: pendingTranslation("Watch"),
        children: [
          MenuGroupComponent(
            items: [
              Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Text(
                  statusText,
                  style: TextStyles.body.copyWith(color: colors.textBase),
                ),
              ),
            ],
          ),
          if (service.errorCode != null) ...[
            const SizedBox(height: Spacing.md),
            Text(
              _errorMessage(service.errorCode!),
              style: TextStyles.body.copyWith(color: warningColor),
            ),
          ],
          if (state.canPublish && service.heldCount < service.totalCount) ...[
            const SizedBox(height: Spacing.md),
            Text(
              pendingTranslation(
                "Your watch can hold ${service.heldCount} of your ${service.totalCount} codes.",
              ),
              style: TextStyles.body.copyWith(color: colors.textLight),
            ),
          ],
          if (service.omittedCount > 0) ...[
            const SizedBox(height: Spacing.md),
            Text(
              service.omittedCount == 1
                  ? pendingTranslation(
                      "1 account couldn't be added to your watch.",
                    )
                  : pendingTranslation(
                      "${service.omittedCount} accounts couldn't be added to your watch.",
                    ),
              style: TextStyles.body.copyWith(color: colors.textLight),
            ),
          ],
          if (state.phase == WatchPhase.approval) ...[
            const SizedBox(height: Spacing.lg),
            ButtonComponent(
              label: pendingTranslation("Share codes"),
              isDisabled: busy && activeAction != _WatchAction.approve,
              shouldShowSuccessState: false,
              onTap: () =>
                  _authenticated(_WatchAction.approve, service.approve),
            ),
          ],
          if (canRefresh) ...[
            const SizedBox(height: Spacing.lg),
            ButtonComponent(
              label: pendingTranslation("Check again"),
              variant: ButtonComponentVariant.secondary,
              isDisabled: busy && activeAction != _WatchAction.refresh,
              shouldShowSuccessState: false,
              onTap: () => _run(_WatchAction.refresh, service.refresh),
            ),
          ],
          if (state.canDisable) ...[
            const SizedBox(height: Spacing.xl),
            MenuGroupComponent(
              items: [
                MenuComponent(
                  title: pendingTranslation("Stop sharing"),
                  titleColor: warningColor,
                  showOnlyLoadingState: true,
                  onTap: busy && activeAction != _WatchAction.disable
                      ? null
                      : () => _authenticated(
                          _WatchAction.disable,
                          service.disable,
                        ),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );

  Future<void> _authenticated(
    _WatchAction kind,
    Future<void> Function(WatchState target, String scope) action,
  ) {
    final target = service.state;
    final scope = service.vaultScope();
    return _run(kind, () async {
      if (await _authenticate(context) && mounted) await action(target, scope);
    });
  }

  Future<void> _run(_WatchAction kind, Future<void> Function() action) async {
    if (busy) return;
    setState(() => activeAction = kind);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        showToast(
          context,
          _errorMessage(
            error is PlatformException ? error.code : 'watchUnavailable',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => activeAction = null);
    }
  }
}

Future<bool> _authenticate(BuildContext context) async {
  final auth = LocalAuthenticationService.instance;
  final supported = await auth.isLocalAuthSupportedOnDevice();
  if (!context.mounted) return false;
  if (!supported && !LockScreenSettings.instance.getIsAppLockSet()) {
    showToast(
      context,
      pendingTranslation("Set up a device passcode or an Ente app lock first."),
    );
    return false;
  }
  return auth.requestLocalAuthentication(
    context,
    pendingTranslation("Authenticate to change watch sharing."),
    useDebugAuthCache: false,
  );
}

String _errorMessage(String code) => switch (code) {
  'phoneLocked' => pendingTranslation("Unlock Ente Auth, then try again."),
  _ => pendingTranslation(
    "Couldn't update your watch. Open Ente Auth on both devices and try again.",
  ),
};
