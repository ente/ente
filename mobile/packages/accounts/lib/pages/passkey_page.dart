import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:ente_accounts/ente_accounts.dart';
import 'package:ente_accounts/models/errors.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/alert_bottom_sheet.dart';
import 'package:ente_ui/components/buttons/gradient_button.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher_string.dart';

class PasskeyPage extends StatefulWidget {
  final BaseConfiguration config;
  final String sessionID;
  final String totp2FASessionID;
  final String accountsUrl;
  final String redirectUrl;
  final String clientPackage;

  const PasskeyPage(
    this.config,
    this.sessionID, {
    required this.totp2FASessionID,
    required this.accountsUrl,
    required this.redirectUrl,
    required this.clientPackage,
    super.key,
  });

  @override
  State<PasskeyPage> createState() => _PasskeyPageState();
}

class _PasskeyPageState extends State<PasskeyPage> {
  final Logger _logger = Logger("PasskeyPage");

  @override
  void initState() {
    launchPasskey();
    _initDeepLinks();
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> launchPasskey() async {
    await launchUrlString(
      "${widget.accountsUrl}/passkeys/verify?"
      "passkeySessionID=${widget.sessionID}"
      "&redirect=${widget.redirectUrl}"
      "&clientPackage=${widget.clientPackage}",
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
      if (mounted) {
        showToast(context, context.strings.passKeyPendingVerification);
      }
      return;
    } on PassKeySessionExpiredError {
      if (!mounted) {
        return;
      }
      await showAlertBottomSheet(
        context,
        title: context.strings.loginSessionExpired,
        message: context.strings.loginSessionExpiredDetails,
        assetPath: 'assets/warning-grey.png',
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    } catch (e, s) {
      _logger.severe("failed to check status", e, s);
      if (mounted) {
        showGenericErrorDialog(context: context, error: e).ignore();
      }
      return;
    }
    await UserService.instance.onPassKeyVerified(
      mounted ? context : null,
      response,
    );
  }

  Future<void> _handleDeeplink(String? link) async {
    if (!context.mounted ||
        widget.config.hasConfiguredAccount() ||
        link == null) {
      _logger.warning('ignored deeplink: contextMounted ${context.mounted}');
      return;
    }
    try {
      final expectedPrefix = widget.redirectUrl.toLowerCase();
      if (mounted && link.toLowerCase().startsWith(expectedPrefix)) {
        if (widget.config.isLoggedIn()) {
          _logger.info('ignored deeplink: already configured');
          showToast(context, 'Account is already configured.');
          return;
        }
        final parsedUri = Uri.parse(link);
        final sessionID = parsedUri.queryParameters['passkeySessionID'];
        if (sessionID != widget.sessionID) {
          showToast(context, "Session ID mismatch");
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
          mounted ? context : null,
          json,
        );
      } else {
        _logger.info('ignored deeplink: $link mounted $mounted');
      }
    } catch (e, s) {
      _logger.severe('passKey: failed to handle deeplink', e, s);
      if (mounted) {
        showGenericErrorDialog(context: context, error: e).ignore();
      }
    }
  }

  Future<bool> _initDeepLinks() async {
    final appLinks = AppLinks();
    // Attach a listener to the stream
    appLinks.stringLinkStream.listen(
      _handleDeeplink,
      onError: (err) {
        _logger.severe(err);
      },
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return Scaffold(
      backgroundColor: colorScheme.backgroundBase,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.backgroundBase,
        centerTitle: true,
        title: SvgPicture.asset(
          'assets/svg/app-logo.svg',
          colorFilter: ColorFilter.mode(
            colorScheme.primary700,
            BlendMode.srcIn,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: colorScheme.primary700,
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: _getBody(),
    );
  }

  Widget _getBody() {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text(
              context.strings.passkeyAuthTitle,
              style: textTheme.h3Bold.copyWith(color: colorScheme.textBase),
            ),
            Text(
              context.strings.waitingForVerification,
              style: textTheme.body.copyWith(color: colorScheme.textMuted),
            ),
            const SizedBox(height: 24),
            GradientButton(
              text: context.strings.tryAgain,
              onTap: () => launchPasskey(),
            ),
            const SizedBox(height: 16),
            GradientButton(
              text: context.strings.checkStatus,
              buttonType: GradientButtonType.secondary,
              onTap: () async {
                try {
                  await checkStatus();
                } catch (e) {
                  debugPrint('failed to check status %e');
                  if (mounted) {
                    showGenericErrorDialog(context: context, error: e).ignore();
                  }
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                widget.totp2FASessionID.isNotEmpty
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          routeToPage(
                            context,
                            TwoFactorAuthenticationPage(
                              widget.totp2FASessionID,
                            ),
                          );
                        },
                        child: Text(
                          context.strings.loginWithTOTP,
                          style: textTheme.body.copyWith(
                            color: colorScheme.primary700,
                            decoration: TextDecoration.underline,
                            decorationColor: colorScheme.primary700,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    UserService.instance.recoverTwoFactor(
                      context,
                      widget.sessionID,
                      TwoFactorType.passkey,
                    );
                  },
                  child: Text(
                    context.strings.recoverAccount,
                    style: textTheme.body.copyWith(
                      color: colorScheme.primary700,
                      decoration: TextDecoration.underline,
                      decorationColor: colorScheme.primary700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
