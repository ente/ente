import "dart:async";
import 'dart:convert';

import "package:app_links/app_links.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/core/errors.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/account/two_factor.dart";
import 'package:photos/services/account/user_service.dart';
import "package:photos/ui/account/two_factor_authentication_page.dart";
import "package:photos/ui/components/alert_bottom_sheet.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/dialog_util.dart";
import 'package:url_launcher/url_launcher_string.dart';

class PasskeyPage extends StatefulWidget {
  final String sessionID;
  final String totp2FASessionID;
  final String accountsUrl;

  const PasskeyPage(
    this.sessionID, {
    required this.totp2FASessionID,
    required this.accountsUrl,
    super.key,
  });

  @override
  State<PasskeyPage> createState() => _PasskeyPageState();
}

class _PasskeyPageState extends State<PasskeyPage> {
  final Logger _logger = Logger("PasskeyPage");
  late StreamSubscription<Uri?> linkStreamSubscription;

  @override
  void initState() {
    launchPasskey();
    _initDeepLinks();
    super.initState();
  }

  @override
  void dispose() {
    linkStreamSubscription.cancel();
    super.dispose();
  }

  Future<void> launchPasskey() async {
    await launchUrlString(
      "${widget.accountsUrl}/passkeys/verify?"
      "passkeySessionID=${widget.sessionID}"
      "&redirect=ente://passkey"
      "&clientPackage=io.ente.photos",
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> checkStatus() async {
    late dynamic response;
    try {
      response = await UserService.instance.getTokenForPasskeySession(
        widget.sessionID,
      );
    } on PassKeySessionNotVerifiedError {
      if (!mounted) return;
      showToast(context, context.l10n.passKeyPendingVerification);
      return;
    } on PassKeySessionExpiredError {
      if (!mounted) return;
      await showAlertBottomSheet(
        context,
        title: context.l10n.loginSessionExpired,
        message: context.l10n.loginSessionExpiredDetails,
        assetPath: 'assets/warning-grey.png',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    } catch (e, s) {
      _logger.severe("failed to check status", e, s);
      if (!mounted) return;
      showGenericErrorBottomSheet(context: context, error: e).ignore();
      return;
    }
    if (!mounted) return;
    await UserService.instance.onPassKeyVerified(context, response);
  }

  Future<void> _handleDeeplink(Uri? uri) async {
    if (!mounted ||
        Configuration.instance.hasConfiguredAccount() ||
        uri == null) {
      _logger.warning(
        'ignored deeplink: mounted $mounted hasConfiguredAccount ${Configuration.instance.hasConfiguredAccount()}',
      );
      return;
    }
    final link = uri.toString();
    try {
      if (mounted && link.toLowerCase().startsWith("ente://passkey")) {
        if (Configuration.instance.isLoggedIn()) {
          _logger.info('ignored deeplink: already configured');
          showToast(
            context,
            AppLocalizations.of(context).accountIsAlreadyConfigured,
          );
          return;
        }
        final parsedUri = Uri.parse(link);
        final sessionID = parsedUri.queryParameters['passkeySessionID'];
        if (sessionID != widget.sessionID) {
          showToast(context, AppLocalizations.of(context).sessionIdMismatch);
          _logger.warning('ignored deeplink: sessionID mismatch');
          return;
        }
        final String? authResponse = parsedUri.queryParameters['response'];
        String base64String = authResponse!.toString();
        while (base64String.length % 4 != 0) {
          base64String += '=';
        }
        final res = utf8.decode(base64.decode(base64String));
        final json = jsonDecode(res) as Map<String, dynamic>;
        await UserService.instance.onPassKeyVerified(context, json);
      } else {
        _logger.info('ignored deeplink: $link mounted $mounted');
      }
    } catch (e, s) {
      _logger.severe('passKey: failed to handle deeplink', e, s);
      if (!mounted) return;
      showGenericErrorBottomSheet(context: context, error: e).ignore();
    }
  }

  Future<bool> _initDeepLinks() async {
    final appLinks = AppLinks();
    // Attach a listener to the stream
    linkStreamSubscription = appLinks.uriLinkStream.listen(
      _handleDeeplink,
      onError: (err) {
        _logger.severe(err);
      },
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.backgroundBase,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: colors.iconColor,
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          AppLocalizations.of(context).passkey,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        centerTitle: true,
      ),
      body: _getBody(),
    );
  }

  Widget _getBody() {
    final colors = context.componentColors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const Spacer(),
            Text(
              context.l10n.waitingForVerification,
              style: TextStyles.body.copyWith(color: colors.textLight),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            ButtonComponent(
              label: context.l10n.tryAgain,
              onTap: () => launchPasskey(),
            ),
            const SizedBox(height: 16),
            ButtonComponent(
              label: context.l10n.checkStatus,
              variant: ButtonComponentVariant.secondary,
              shouldSurfaceExecutionStates: true,
              onTap: () async {
                try {
                  await checkStatus();
                } catch (e) {
                  debugPrint('failed to check status $e');
                  if (!mounted) return;
                  showGenericErrorBottomSheet(
                    context: context,
                    error: e,
                  ).ignore();
                }
              },
            ),
            if (widget.totp2FASessionID.isNotEmpty) ...[
              const SizedBox(height: 16),
              ButtonComponent(
                label: context.l10n.loginWithTOTP,
                variant: ButtonComponentVariant.link,
                size: ButtonComponentSize.small,
                onTap: () async {
                  // ignore: unawaited_futures
                  routeToPage(
                    context,
                    TwoFactorAuthenticationPage(widget.totp2FASessionID),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            ButtonComponent(
              label: context.l10n.recoverAccount,
              variant: ButtonComponentVariant.link,
              size: ButtonComponentSize.small,
              onTap: () async {
                // ignore: unawaited_futures
                UserService.instance.recoverTwoFactor(
                  context,
                  widget.sessionID,
                  TwoFactorType.passkey,
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
