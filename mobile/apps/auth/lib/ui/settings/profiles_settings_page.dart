import 'dart:async';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/profile.dart';
import 'package:ente_auth/onboarding/view/onboarding_page.dart';
import 'package:ente_auth/services/profile_service.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/home_page.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_item.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:logging/logging.dart';

class ProfilesSettingsPage extends StatefulWidget {
  const ProfilesSettingsPage({super.key});

  @override
  State<ProfilesSettingsPage> createState() => _ProfilesSettingsPageState();
}

class _ProfilesSettingsPageState extends State<ProfilesSettingsPage> {
  final _logger = Logger('ProfilesSettingsPage');
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final service = ProfileService.instance;
    final contents = <Widget>[];

    for (final profile in service.profiles) {
      final isActive = profile.scope == service.activeScope;
      contents.addAll([
        AuthSettingsItem(
          title: profile.displayName(l10n.offlineVault),
          icon: profile.isOffline
              ? HugeIcons.strokeRoundedCloudOff
              : HugeIcons.strokeRoundedUser,
          showChevron: false,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive)
                Icon(
                  Icons.check,
                  color: context.componentColors.primary,
                  size: IconSizes.medium,
                ),
              // Offline vaults have no email to tell them apart.
              if (profile.isOffline)
                IconButton(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit02),
                  iconSize: IconSizes.small,
                  tooltip: l10n.renameVault,
                  onPressed: _isBusy ? null : () => _rename(profile),
                ),
            ],
          ),
          onTap: isActive ? null : () => _switchTo(profile),
        ),
        const SizedBox(height: Spacing.sm),
      ]);
    }

    final canAdd = service.canAddProfile;
    contents.addAll([
      const SizedBox(height: Spacing.md),
      AuthSettingsItem(
        title: l10n.addAccount,
        icon: HugeIcons.strokeRoundedUserAdd01,
        semanticsIdentifier: 'auth_settings_add_account',
        // A null onTap is what marks the row disabled.
        showChevron: canAdd,
        onTap: (canAdd && !_isBusy) ? _addAccount : null,
      ),
      if (!canAdd) ...[
        const SizedBox(height: Spacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: Text(
            l10n.maxAccountsReached(ProfileService.maxProfiles),
            style: getEnteTextTheme(context).miniMuted,
          ),
        ),
      ],
    ]);

    return AuthSettingsPageScaffold(title: l10n.accounts, children: contents);
  }

  Future<void> _switchTo(Profile profile) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final dialog = createProgressDialog(context, context.l10n.pleaseWait);
    await dialog.show();
    try {
      await ProfileService.instance.switchTo(profile.scope);
    } catch (e, s) {
      _logger.severe("Failed to switch to $profile", e, s);
      await dialog.hide();
      if (mounted) {
        setState(() => _isBusy = false);
        await showGenericErrorDialog(context: context, error: e);
      }
      return;
    }
    await dialog.hide();
    if (!mounted) return;
    // Every page below holds the previous vault's codes.
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  Future<void> _rename(Profile profile) async {
    final l10n = context.l10n;
    await showTextInputDialog(
      context,
      title: l10n.renameVault,
      submitButtonLabel: l10n.save,
      hintText: l10n.vaultNameHint,
      initialValue: profile.label ?? "",
      maxLength: 50,
      textCapitalization: TextCapitalization.words,
      onSubmit: (String name) async {
        await ProfileService.instance.rename(profile.scope, name);
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _addAccount() async {
    setState(() => _isBusy = true);
    final navigator = Navigator.of(context, rootNavigator: true);
    final service = ProfileService.instance;
    final scope = await service.beginAdd();
    if (!mounted) {
      // Disposed while beginAdd() was re-pointing the databases. Nothing has
      // signed in, so hand the scope back rather than leaving the app on a
      // blank, unregistered vault.
      await service.abortAdd(scope);
      return;
    }
    // The sign in flow navigates to the home page itself once it completes,
    // and ProfileService commits the new profile when it sees the sign in.
    final signedIn = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const OnboardingPage()));
    // Consumed before the mounted check: a successful sign in resets the
    // navigation stack and unmounts this page, but a rejected duplicate still
    // has to be reported.
    if (service.consumeRejectedDuplicateAdd()) {
      if (mounted) setState(() => _isBusy = false);
      if (!navigator.mounted) return;
      // The sign in flow has already pushed its own home page for the scope
      // abortAdd just erased, so send the user back to the profile they were
      // on before reporting. Not awaited: the route only completes once it is
      // popped.
      unawaited(navigator.pushNamedAndRemoveUntil('/', (route) => false));
      // The root navigator outlives this page, which the sign in flow has
      // usually unmounted by now.
      // ignore: use_build_context_synchronously
      final l10n = navigator.context.l10n;
      await showErrorDialog(
        // ignore: use_build_context_synchronously
        navigator.context,
        l10n.accounts,
        l10n.alreadySignedInToAccount,
      );
      if (mounted) setState(() {});
      return;
    }
    if (mounted) setState(() => _isBusy = false);
    // Deliberately not gated on mounted: a successful sign in unmounts this
    // page, and skipping the decision below would leave the allocated scope
    // neither committed nor rolled back.
    await _finishAdd(scope, signedIn: signedIn == true, navigator: navigator);
  }

  // Commits the scope [beginAdd] allocated, or hands it back if the user never
  // completed the sign in. The navigator is passed in because this runs after
  // the sign in flow may have unmounted the page.
  Future<void> _finishAdd(
    String scope, {
    required bool signedIn,
    required NavigatorState navigator,
  }) async {
    final service = ProfileService.instance;
    // The sign in listener inside beginAdd() may have committed already, in
    // which case aborting here would delete the account that was just added.
    if (service.profiles.any((profile) => profile.scope == scope)) return;
    final config = Configuration.instance;
    // An offline vault is a completed add even though nobody signed in, so it
    // must not fall through to the abort below.
    final wentOffline =
        !config.hasConfiguredAccount() && config.hasOptedForOfflineMode();
    if (signedIn || config.hasConfiguredAccount() || wentOffline) {
      await service.commitAdd(scope);
      if (wentOffline) {
        // The offline flow only pushes over this page, unlike the sign in flow
        // which resets the stack.
        unawaited(navigator.pushNamedAndRemoveUntil('/', (route) => false));
      }
      return;
    }
    // The user backed out; drop the half configured scope.
    await service.abortAdd(scope);
    if (mounted) setState(() {});
  }
}
