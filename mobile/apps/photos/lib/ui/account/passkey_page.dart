import "dart:async";
import 'dart:convert';
import 'dart:typed_data';

import "package:app_links/app_links.dart";
import "package:ente_base/models/accounts.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/services/account/user_service.dart';
import "package:photos/ui/account/onboarding_page_scaffold.dart";
import "package:photos/ui/account/two_factor_authentication_page.dart";
import "package:photos/ui/components/alert_bottom_sheet.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/dialog_util.dart";
import 'package:url_launcher/url_launcher_string.dart';

class PasskeyPage extends StatefulWidget {
  final String sessionID;
  final Uint8List? keyEncryptionKey;
  final String totp2FASessionID;
  final String accountsUrl;

  const PasskeyPage(
    this.sessionID, {
    required this.totp2FASessionID,
    required this.accountsUrl,
    this.keyEncryptionKey,
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
    Map<String, dynamic>? response;
    try {
      response = await UserService.instance.getTokenForPasskeySession(
        widget.sessionID,
      );
    } on AccountsError_SessionExpired {
      if (!mounted) return;
      await showAlertBottomSheet(
        context,
        title: context.strings.loginSessionExpired,
        message: context.strings.loginSessionExpiredDetails,
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
    if (response == null) {
      showToast(context, context.strings.passKeyPendingVerification);
      return;
    }
    await UserService.instance.onPassKeyVerified(
      context,
      response,
      keyEncryptionKey: widget.keyEncryptionKey,
    );
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
          showToast(context, context.strings.accountIsAlreadyConfigured);
          return;
        }
        final parsedUri = Uri.parse(link);
        final sessionID = parsedUri.queryParameters['passkeySessionID'];
        if (sessionID != widget.sessionID) {
          showToast(context, context.strings.sessionIdMismatch);
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
        await UserService.instance.onPassKeyVerified(
          context,
          json,
          keyEncryptionKey: widget.keyEncryptionKey,
        );
      } else {
        _logger.info(
          'ignored deeplink: ${baseUrlForLogging(link)} mounted $mounted',
        );
      }
    } catch (e, s) {
      _logger.severe('passKey: failed to handle deeplink', e, s);
      if (!mounted) return;
      showGenericErrorBottomSheet(context: context, error: e).ignore();
    }
  }

  Future<bool> _initDeepLinks() async {
    final appLinks = AppLinks();
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

    return OnboardingPageScaffold(
      title: context.strings.passkeyAuthTitle,
      illustration: OnboardingIllustration.key,
      isBodyCentered: true,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.strings.waitingForVerification,
            style: TextStyles.body.copyWith(color: colors.textBase),
            textAlign: TextAlign.center,
          ),
          if (widget.totp2FASessionID.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            ButtonComponent(
              label: context.strings.useTwoFactorInstead,
              variant: ButtonComponentVariant.link,
              size: ButtonComponentSize.small,
              onTap: () async {
                // ignore: unawaited_futures
                routeToPage(
                  context,
                  TwoFactorAuthenticationPage(
                    widget.totp2FASessionID,
                    keyEncryptionKey: widget.keyEncryptionKey,
                  ),
                );
              },
            ),
          ],
        ],
      ),
      actions: [
        ButtonComponent(
          label: context.strings.tryAgain,
          onTap: () => launchPasskey(),
        ),
        ButtonComponent(
          label: context.strings.checkStatus,
          variant: ButtonComponentVariant.secondary,
          shouldSurfaceExecutionStates: true,
          onTap: () async {
            try {
              await checkStatus();
            } catch (e) {
              debugPrint('failed to check status $e');
              if (!context.mounted) return;
              showGenericErrorBottomSheet(context: context, error: e).ignore();
            }
          },
        ),
        ButtonComponent(
          label: context.strings.recoverAccount,
          variant: ButtonComponentVariant.link,
          onTap: () async {
            // ignore: unawaited_futures
            UserService.instance.recoverTwoFactor(
              context,
              widget.sessionID,
              TwoFactorType.passkey,
            );
          },
        ),
      ],
    );
  }
}
