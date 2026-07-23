import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_crypto/ente_crypto.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:logging/logging.dart";
import 'package:photos/core/configuration.dart';
import "package:photos/gateways/users/models/srp.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/ui/components/buttons/button_widget.dart"
    show ButtonAction;
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/email_util.dart";

// LoginPasswordVerificationPage is a page that allows the user to enter their password to verify their identity.
// If the password is correct, then the user is either directed to
// PasswordReentryPage (if the user has not yet set up 2FA) or TwoFactorAuthenticationPage (if the user has set up 2FA).
// In the PasswordReentryPage, the password is auto-filled based on the
// volatile password.
class LoginPasswordVerificationPage extends StatefulWidget {
  final SrpAttributes srpAttributes;

  const LoginPasswordVerificationPage({super.key, required this.srpAttributes});

  @override
  State<LoginPasswordVerificationPage> createState() =>
      _LoginPasswordVerificationPageState();
}

class _LoginPasswordVerificationPageState
    extends State<LoginPasswordVerificationPage> {
  final _passwordController = TextEditingController();
  String? email;
  bool _hasPassword = false;
  final Logger _logger = Logger("LoginPasswordVerificationPage");

  @override
  void initState() {
    super.initState();
    email = Configuration.instance.getEmail();
    if (kDebugMode) {
      _passwordController.text = const String.fromEnvironment("password");
      _hasPassword = _passwordController.text.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
          AppLocalizations.of(context).logInLabel,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        centerTitle: true,
      ),
      body: _getBody(),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ButtonComponent(
          key: const ValueKey("verifyPasswordButton"),
          label: AppLocalizations.of(context).logInLabel,
          isDisabled: !_hasPassword,
          onTap: _verifyEnteredPassword,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Future<void> _verifyEnteredPassword() async {
    if (!_hasPassword) {
      return;
    }
    FocusScope.of(context).unfocus();
    await verifyPassword(context, _passwordController.text);
  }

  Widget _getBody() {
    return AutofillGroup(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 24),
          Visibility(
            visible: false,
            child: TextFormField(
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              initialValue: email,
              textInputAction: TextInputAction.next,
            ),
          ),
          TextInputComponent(
            key: const ValueKey("passwordInputField"),
            label: AppLocalizations.of(context).password,
            hintText: AppLocalizations.of(context).enterYourPassword,
            controller: _passwordController,
            isPasswordInput: true,
            isRequired: true,
            autocorrect: false,
            autofocus: true,
            shouldUnfocusOnClearOrSubmit: true,
            onSubmit: (_) => _verifyEnteredPassword(),
            onChanged: (value) {
              final hasPassword = value.isNotEmpty;
              if (_hasPassword != hasPassword) {
                setState(() {
                  _hasPassword = hasPassword;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ButtonComponent(
              variant: ButtonComponentVariant.link,
              label: AppLocalizations.of(context).forgotPassword,
              size: ButtonComponentSize.small,
              onTap: () async {
                await UserService.instance.sendOtt(
                  context,
                  email!,
                  isResetPasswordScreen: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> verifyPassword(BuildContext context, String password) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).pleaseWait,
      isDismissible: true,
    );
    await dialog.show();
    try {
      if (!context.mounted) return;
      await UserService.instance.verifyEmailViaPassword(
        context,
        widget.srpAttributes,
        password,
        dialog,
      );
    } on DioException catch (e, s) {
      await dialog.hide();
      if (e.response != null && e.response!.statusCode == 401) {
        _logger.severe('server reject, failed verify SRP login', e, s);
        if (!context.mounted) return;
        await _showContactSupportDialog(
          context,
          AppLocalizations.of(context).incorrectPasswordTitle,
          AppLocalizations.of(context).pleaseTryAgain,
        );
      } else {
        _logger.severe('API failure during SRP login ${e.type}', e, s);
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout) {
          if (!context.mounted) return;
          await _showContactSupportDialog(
            context,
            AppLocalizations.of(context).noInternetConnection,
            AppLocalizations.of(
              context,
            ).pleaseCheckYourInternetConnectionAndTryAgain,
          );
        } else {
          if (!context.mounted) return;
          await _showContactSupportDialog(
            context,
            AppLocalizations.of(context).somethingWentWrong,
            AppLocalizations.of(context).verificationFailedPleaseTryAgain,
          );
        }
      }
    } catch (e, s) {
      _logger.info('error during loginViaPassword', e);
      await dialog.hide();
      if (e is LoginKeyDerivationError) {
        _logger.severe('loginKey derivation error', e, s);
        // LoginKey err, perform regular login via ott verification
        if (!context.mounted) return;
        await UserService.instance.sendOtt(
          context,
          email!,
          isCreateAccountScreen: true,
        );
        return;
      } else if (e is KeyDerivationError) {
        // device is not powerful enough to perform derive key
        if (!context.mounted) return;
        final dialogChoice = await showChoiceDialog(
          context,
          title: AppLocalizations.of(context).recreatePasswordTitle,
          body: AppLocalizations.of(context).recreatePasswordBody,
          firstButtonLabel: AppLocalizations.of(context).useRecoveryKey,
        );
        if (dialogChoice?.action == ButtonAction.first && context.mounted) {
          await UserService.instance.sendOtt(
            context,
            email!,
            isResetPasswordScreen: true,
          );
        }
        return;
      } else {
        _logger.severe('unexpected error while verifying password', e, s);
        if (!context.mounted) return;
        await _showContactSupportDialog(
          context,
          AppLocalizations.of(context).oops,
          AppLocalizations.of(context).verificationFailedPleaseTryAgain,
        );
      }
    }
  }

  Future<void> _showContactSupportDialog(
    BuildContext context,
    String title,
    String message,
  ) async {
    final dialogChoice = await showChoiceDialog(
      context,
      title: title,
      body: message,
      firstButtonLabel: AppLocalizations.of(context).contactSupport,
      secondButtonLabel: AppLocalizations.of(context).ok,
    );
    if (dialogChoice?.action == ButtonAction.first && context.mounted) {
      await sendLogs(
        context,
        AppLocalizations.of(context).contactSupport,
        "support@ente.com",
        postShare: () {},
      );
    }
  }
}
