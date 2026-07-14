import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/network/endpoint_config.dart";
import "package:photos/core/network/endpoint_policy.dart";
import "package:photos/core/network/endpoint_switcher.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/account/login_page.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";

typedef LocalLogout = Future<void> Function();

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({
    super.key,
    this.config,
    this.switcher,
    this.isSignedIn,
    this.localLogout,
    this.onSwitchComplete,
  });

  final EndpointConfig? config;
  final EndpointSwitcher? switcher;
  final bool? isSignedIn;
  final LocalLogout? localLogout;
  final VoidCallback? onSwitchComplete;

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  static final _logger = Logger("ServerSettingsPage");

  late final EndpointConfig _config;
  late final EndpointSwitcher _switcher;
  late final bool _ownsSwitcher;
  late final bool _requiresLocalAccountCleanup;
  late final LocalLogout _localLogout;
  late final TextEditingController _controller;

  String? _message;
  TextInputComponentMessageType _messageType =
      TextInputComponentMessageType.helper;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _config =
        widget.config ?? widget.switcher?.endpointConfig ?? endpointConfig;
    _ownsSwitcher = widget.switcher == null;
    _switcher = widget.switcher ?? EndpointSwitcher(_config);
    _requiresLocalAccountCleanup =
        (widget.isSignedIn ?? Configuration.instance.isLoggedIn()) ||
        _config.hasLocalAccountState;
    _localLogout = widget.localLogout ?? Configuration.instance.logout;
    _controller = TextEditingController(text: _config.endpoint);
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_ownsSwitcher) {
      _switcher.close(force: true);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.componentColors;

    return SettingsPageScaffold(
      title: l10n.serverEndpoint,
      children: [
        const SizedBox(height: 12),
        Text(
          l10n.customEndpoint(endpoint: _config.endpoint),
          key: const ValueKey("activeServerOrigin"),
          style: TextStyles.body.copyWith(color: colors.textLight),
        ),
        const SizedBox(height: 24),
        TextInputComponent(
          key: const ValueKey("serverOriginInput"),
          label: l10n.serverEndpoint,
          hintText: "https://museum.example.com",
          controller: _controller,
          autocorrect: false,
          keyboardType: TextInputType.url,
          shouldUnfocusOnClearOrSubmit: true,
          message: _message,
          messageType: _messageType,
          onChanged: (_) => _clearMessage(),
          onSubmit: _isBusy ? null : (_) => _validateAndSwitch(),
        ),
        const SizedBox(height: 24),
        ButtonComponent(
          key: const ValueKey("verifyAndSwitchServerButton"),
          label: l10n.verifyAndSwitchServer,
          isDisabled: _isBusy,
          onTap: _isBusy ? null : _validateAndSwitch,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.serverVerificationDescription,
          style: TextStyles.mini.copyWith(color: colors.textLighter),
        ),
      ],
    );
  }

  Future<void> _validateAndSwitch() async {
    FocusScope.of(context).unfocus();
    _setBusy(true);
    _clearMessage();

    try {
      final candidate = await _switcher.validateCandidate(
        _controller.text.trim(),
      );
      if (!mounted) return;
      if (_switcher.isCurrent(candidate)) {
        _setMessage(
          AppLocalizations.of(context).serverAlreadyActive,
          TextInputComponentMessageType.success,
        );
        return;
      }

      if (_requiresLocalAccountCleanup &&
          !await _confirmSignedInSwitch(candidate.origin)) {
        return;
      }

      if (_requiresLocalAccountCleanup) {
        await _localLogout();
      }
      await _switcher.activateAfterLocalLogout(candidate);

      if (!mounted) return;
      _completeSwitch();
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to switch the configured server",
        error,
        stackTrace,
      );
      if (!mounted) return;
      _setMessage(_messageFor(error), TextInputComponentMessageType.error);
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> _confirmSignedInSwitch(String candidate) async {
    final colors = context.componentColors;
    final result = await showBottomSheetComponent<bool>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: AppLocalizations.of(context).changeServer,
        closeTooltip: AppLocalizations.of(context).cancel,
        closeResult: false,
        isScrollable: true,
        initialChildSize: 0.9,
        content: Text(
          AppLocalizations.of(context).serverSwitchWarning(
            currentEndpoint: _config.endpoint,
            newEndpoint: candidate,
          ),
          style: TextStyles.body.copyWith(color: colors.textLight),
        ),
        actions: [
          ButtonComponent(
            label: AppLocalizations.of(context).logOutAndSwitch,
            variant: ButtonComponentVariant.critical,
            shouldSurfaceExecutionStates: false,
            onTap: () => Navigator.of(sheetContext).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _completeSwitch() {
    if (widget.onSwitchComplete != null) {
      widget.onSwitchComplete!();
      return;
    }

    final navigator = Navigator.of(context);
    unawaited(
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => route.isFirst,
      ),
    );
  }

  String _messageFor(Object error) {
    final l10n = AppLocalizations.of(context);
    return switch (error) {
      EndpointPolicyException(
        reason: EndpointPolicyFailureReason.invalidConfigurableEndpoint,
      ) =>
        l10n.invalidEndpointMessage,
      EndpointPolicyException(
        reason: EndpointPolicyFailureReason.accountStateNotCleared,
      ) =>
        l10n.completeLocalLogoutBeforeChangingServer,
      EndpointPolicyException() => l10n.serverWasNotChanged,
      EndpointProbeException(
        reason: EndpointProbeFailureReason.invalidResponse,
      ) =>
        l10n.invalidMuseumResponse,
      EndpointProbeException() => l10n.serverCouldNotBeVerified,
      _ => l10n.serverWasNotChanged,
    };
  }

  void _clearMessage() {
    if (_message == null || !mounted) return;
    setState(() {
      _message = null;
      _messageType = TextInputComponentMessageType.helper;
    });
  }

  void _setMessage(String message, TextInputComponentMessageType type) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageType = type;
    });
  }

  void _setBusy(bool value) {
    if (!mounted || _isBusy == value) return;
    setState(() {
      _isBusy = value;
    });
  }
}

class ConfigurableServerLink extends StatelessWidget {
  const ConfigurableServerLink({
    super.key,
    this.config,
    this.foregroundColor,
    this.onTap,
  });

  final EndpointConfig? config;
  final Color? foregroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveConfig = config ?? endpointConfig;
    if (!effectiveConfig.isConfigurable) {
      return const SizedBox.shrink();
    }

    final label = AppLocalizations.of(
      context,
    ).customEndpoint(endpoint: effectiveConfig.endpoint);
    return TextButton(
      key: const ValueKey("configurableServerLink"),
      style: TextButton.styleFrom(foregroundColor: foregroundColor),
      onPressed:
          onTap ??
          () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ServerSettingsPage(config: effectiveConfig),
              ),
            );
          },
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(decoration: TextDecoration.underline),
      ),
    );
  }
}
