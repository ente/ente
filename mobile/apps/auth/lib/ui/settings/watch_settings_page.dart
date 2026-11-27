import 'dart:async';
import 'dart:io';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/watch/snapshot.dart';
import 'package:ente_auth/models/watch/state.dart';
import 'package:ente_auth/services/watch/selection.dart';
import 'package:ente_auth/services/watch/service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_navigation.dart';
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

enum _WatchAction { disable, refresh }

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
        WatchPhase.pending ||
        WatchPhase.retiring ||
        WatchPhase.failed ||
        WatchPhase.ambiguous => true,
        _ => false,
      };
      final statusText = switch (state.phase) {
        WatchPhase.unavailable =>
          Platform.isIOS
              ? pendingTranslation(
                  "Requires iOS 17 or later and watchOS 10 or later. Pair your Apple Watch and install Ente Auth on it.",
                )
              : pendingTranslation(
                  "Wear OS sync needs Android 8 or later, Wear OS 3 or later, the Google Play version of Ente Auth, and Google Play services on both devices.",
                ),
        WatchPhase.setup => pendingTranslation(
          "Open Ente Auth on your watch and select Set up watch.",
        ),
        WatchPhase.approval => null,
        WatchPhase.pending => pendingTranslation(
          "Changes are waiting for your watch. Open Ente Auth on it to sync.",
        ),
        WatchPhase.synced => pendingTranslation(
          "Your watch has the latest shared accounts.",
        ),
        WatchPhase.retiring => pendingTranslation(
          "Removal is waiting for your watch. Open Ente Auth on it to finish.",
        ),
        WatchPhase.disabled => pendingTranslation(
          "Watch sharing is off. Set up the watch again to share codes.",
        ),
        WatchPhase.failed => pendingTranslation(
          "Could not update the watch. Keep both apps open and try again.",
        ),
        WatchPhase.replacement => pendingTranslation(
          "A new watch setup is waiting. Stop sharing with the previous watch, then approve the new setup.",
        ),
        WatchPhase.ambiguous => pendingTranslation(
          "More than one watch is requesting setup. Connect only the watch you want to set up, then try again.",
        ),
      };
      return AuthSettingsPageScaffold(
        title: pendingTranslation("Watch"),
        children: [
          MenuGroupComponent(
            items: [
              if (statusText != null &&
                  (!state.canPublish || service.sharing != null))
                Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Text(
                    statusText,
                    style: TextStyles.body.copyWith(color: colors.textBase),
                  ),
                ),
              if (state.canPublish)
                SettingsItem(
                  title: pendingTranslation("Accounts on watch"),
                  subtitle: switch (service.sharing?.mode) {
                    WatchSharingMode.all => pendingTranslation("All accounts"),
                    WatchSharingMode.tags => pendingTranslation(
                      "Selected tags",
                    ),
                    null => pendingTranslation("Choose what to share"),
                  },
                  onTap: busy
                      ? null
                      : () => pushAuthSettingsPage(
                          context,
                          _WatchSharingPage(
                            target: state,
                            scope: service.vaultScope(),
                          ),
                        ),
                ),
            ],
          ),
          if (service.errorCode != null) ...[
            const SizedBox(height: Spacing.md),
            Text(
              _errorMessage(context, service.errorCode!),
              style: TextStyles.body.copyWith(color: warningColor),
            ),
          ],
          if (service.omittedCount > 0) ...[
            const SizedBox(height: Spacing.md),
            Text(
              _watchOmittedAccounts(service.omittedCount),
              style: TextStyles.body.copyWith(color: colors.textLight),
            ),
          ],
          if (state.phase == WatchPhase.approval) ...[
            const SizedBox(height: Spacing.lg),
            ButtonComponent(
              label: pendingTranslation("Set up sharing"),
              isDisabled: busy,
              shouldShowSuccessState: false,
              onTap: () => pushAuthSettingsPage(
                context,
                _WatchSharingPage(target: state, scope: service.vaultScope()),
              ),
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
                  title: pendingTranslation("Stop sharing with this watch"),
                  titleColor: warningColor,
                  showOnlyLoadingState: true,
                  onTap: busy && activeAction != _WatchAction.disable
                      ? null
                      : () {
                          final target = service.state;
                          final scope = service.vaultScope();
                          return _run(_WatchAction.disable, () async {
                            if (await _authenticate(context) && mounted) {
                              await service.disable(target, scope);
                            }
                          });
                        },
                ),
              ],
            ),
          ],
        ],
      );
    },
  );

  Future<void> _run(_WatchAction kind, Future<void> Function() action) async {
    if (busy) return;
    setState(() => activeAction = kind);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        showToast(context, _errorMessage(context, _errorCode(error)));
      }
    } finally {
      if (mounted) setState(() => activeAction = null);
    }
  }
}

class _WatchSharingPage extends StatefulWidget {
  const _WatchSharingPage({required this.target, required this.scope});
  final WatchState target;
  final String scope;

  @override
  State<_WatchSharingPage> createState() => _WatchSharingPageState();
}

class _WatchSharingPageState extends State<_WatchSharingPage> {
  final service = WatchService.instance;
  late final Future<List<Code>> codes;
  late final Set<String> initialTags;
  WatchSharingMode? mode;
  final selectedTags = <String>{};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final sharing = service.sharing;
    mode = sharing?.mode;
    initialTags = {...?sharing?.tags};
    selectedTags.addAll(initialTags);
    codes = CodeStore.instance.getAllCodes(requireCompleteRead: true);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Code>>(
    future: codes,
    builder: (context, snapshot) {
      final l10n = context.strings;
      final colors = context.componentColors;
      final tags = {
        ...initialTags,
        for (final code in snapshot.data ?? <Code>[])
          if (!code.hasError && !code.isTrashed) ...code.display.tags,
      }.toList()..sort();
      final sharing = mode == null
          ? null
          : WatchSharing(mode: mode!, tags: selectedTags);
      final count = snapshot.data
          ?.where(WatchSnapshot.supports)
          .where((code) => sharing?.includes(code) ?? false)
          .length;
      final hasUnsupportedCodes =
          snapshot.data?.any(
            (code) =>
                !code.hasError &&
                !code.isTrashed &&
                !WatchSnapshot.supports(code),
          ) ??
          false;
      return AuthSettingsPageScaffold(
        title: pendingTranslation("Accounts on watch"),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (mode != null && count != null && !snapshot.hasError) ...[
                  Text(
                    _watchAccountCount(count),
                    style: TextStyles.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.md),
                ],
                ButtonComponent(
                  label: l10n.save,
                  isDisabled:
                      !snapshot.hasData ||
                      snapshot.hasError ||
                      mode == null ||
                      (mode == WatchSharingMode.tags && selectedTags.isEmpty),
                  shouldShowSuccessState: false,
                  onTap: _save,
                ),
              ],
            ),
          ),
        ),
        children: [
          Text(
            pendingTranslation("Copies two-factor secrets to your watch."),
            style: TextStyles.body.copyWith(color: colors.textLight),
          ),
          const SizedBox(height: Spacing.lg),
          MenuGroupComponent(
            items: [
              _modeRow(
                WatchSharingMode.all,
                pendingTranslation("All accounts"),
                pendingTranslation("Includes future accounts."),
              ),
              _modeRow(
                WatchSharingMode.tags,
                pendingTranslation("Selected tags"),
                pendingTranslation("Includes future matches."),
              ),
            ],
          ),
          if (mode == WatchSharingMode.tags) ...[
            const SizedBox(height: Spacing.lg),
            if (tags.isEmpty && snapshot.hasData)
              Text(
                pendingTranslation("Add tags to your accounts first."),
                style: TextStyles.body,
              )
            else
              MenuGroupComponent(
                items: [
                  for (final tag in tags)
                    _tagRow(
                      tag,
                      snapshot.data
                              ?.where(WatchSnapshot.supports)
                              .where((code) => code.display.tags.contains(tag))
                              .length ??
                          0,
                    ),
                ],
              ),
          ],
          if (snapshot.hasError) ...[
            const SizedBox(height: Spacing.lg),
            Text(
              pendingTranslation(
                "Could not update the watch. Keep both apps open and try again.",
              ),
              style: TextStyles.body,
            ),
          ] else if (!snapshot.hasData) ...[
            const SizedBox(height: Spacing.lg),
            const Center(child: CircularProgressIndicator()),
          ],
          if (hasUnsupportedCodes) ...[
            const SizedBox(height: Spacing.md),
            Text(
              pendingTranslation(
                "Counter-based (HOTP) codes aren’t supported.",
              ),
              style: TextStyles.mini.copyWith(color: colors.textLight),
            ),
          ],
        ],
      );
    },
  );

  Widget _modeRow(WatchSharingMode value, String title, String description) {
    void choose() => setState(() => mode = value);
    return _choiceRow(
      title: title,
      description: description,
      selected: mode == value,
      mutuallyExclusive: true,
      onTap: choose,
      control: RadioComponent(
        selected: mode == value,
        onChanged: busy ? null : (_) => choose(),
      ),
    );
  }

  Widget _tagRow(String tag, int count) {
    final selected = selectedTags.contains(tag);
    void toggle() => setState(() {
      if (!selectedTags.remove(tag)) selectedTags.add(tag);
    });
    return _choiceRow(
      title: tag,
      description: _watchAccountCount(count),
      selected: selected,
      onTap: toggle,
      control: CheckboxComponent(
        selected: selected,
        onChanged: busy ? null : (_) => toggle(),
      ),
    );
  }

  Widget _choiceRow({
    required String title,
    required String description,
    required bool selected,
    required VoidCallback onTap,
    required Widget control,
    bool mutuallyExclusive = false,
  }) {
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: mutuallyExclusive,
      enabled: !busy,
      label: '$title. $description',
      onTap: busy ? null : onTap,
      child: ExcludeSemantics(
        child: MenuComponent(
          title: title,
          subtitle: description,
          selected: selected,
          trailing: control,
          isDisabled: busy,
          onTap: onTap,
          titleBold: true,
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      if (!await _authenticate(context) || !mounted) return;
      await service.share(
        widget.target,
        widget.scope,
        WatchSharing(
          mode: mode!,
          tags: mode == WatchSharingMode.tags ? Set.of(selectedTags) : {},
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        showToast(context, _errorMessage(context, _errorCode(error)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
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
      pendingTranslation(
        "Set up a device passcode or an Ente app PIN or password first.",
      ),
    );
    return false;
  }
  return auth.requestLocalAuthentication(
    context,
    pendingTranslation(
      "Authenticate to change what you share with your watch.",
    ),
    useDebugAuthCache: false,
  );
}

String _errorCode(Object error) =>
    error is PlatformException ? error.code : 'watchUnavailable';

String _errorMessage(BuildContext context, String code) => switch (code) {
  'payloadTooLarge' => pendingTranslation(
    "These accounts exceed the watch transfer limit. Use Selected tags in Watch settings and choose fewer tags.",
  ),
  'wrongEnrollment' || 'staleVault' => pendingTranslation(
    "The account or watch changed. Open this page again.",
  ),
  'phoneLocked' => pendingTranslation("Unlock Ente Auth, then try again."),
  _ => pendingTranslation(
    "Could not update the watch. Keep both apps open and try again.",
  ),
};

String _watchAccountCount(int count) => switch (count) {
  0 => pendingTranslation("No matches"),
  1 => pendingTranslation("1 account"),
  _ => pendingTranslation("$count accounts"),
};

String _watchOmittedAccounts(int count) => count == 1
    ? pendingTranslation(
        "One account could not be sent. Check its OTP settings.",
      )
    : pendingTranslation(
        "$count accounts could not be sent. Check their OTP settings.",
      );
