import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_crypto/ente_crypto.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import 'package:photos/core/configuration.dart';
import "package:photos/gateways/users/models/srp.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/ui/account/onboarding_page_scaffold.dart";
import "package:photos/ui/components/buttons/button_widget.dart"
    show ButtonAction;
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/email_util.dart";

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
  final _passwordFocusNode = FocusNode();
  bool _isSubmitting = false;
  String? email;
  bool _hasPassword = false;
  bool _isPasswordIncorrect = false;
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
    _passwordFocusNode.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingPageScaffold(
      title: context.strings.enterPassword,
      illustration: OnboardingIllustration.password,
      body: _getBody(),
      actions: [
        ButtonComponent(
          key: const ValueKey("verifyPasswordButton"),
          label: context.strings.logInLabel,
          shouldShowSuccessState: false,
          isDisabled: !_hasPassword,
          onTap: _verifyEnteredPassword,
        ),
      ],
    );
  }

  Future<void> _verifyEnteredPassword() async {
    if (!_hasPassword || _isSubmitting) {
      return;
    }
    _isSubmitting = true;
    _passwordFocusNode.unfocus();
    try {
      await verifyPassword(context, _passwordController.text);
    } finally {
      _isSubmitting = false;
    }
  }

  Widget _getBody() {
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            label: context.strings.password,
            hintText: context.strings.enterYourPassword,
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            isPasswordInput: true,
            isRequired: true,
            autocorrect: false,
            autofocus: true,
            shouldUnfocusOnClearOrSubmit: true,
            onSubmit: (_) => _verifyEnteredPassword(),
            message: _isPasswordIncorrect
                ? context.strings.incorrectPasswordTitle
                : null,
            messageType: _isPasswordIncorrect
                ? TextInputComponentMessageType.alert
                : TextInputComponentMessageType.helper,
            onChanged: (value) {
              final hasPassword = value.isNotEmpty;
              if (_hasPassword != hasPassword || _isPasswordIncorrect) {
                setState(() {
                  _hasPassword = hasPassword;
                  _isPasswordIncorrect = false;
                });
              }
            },
          ),
          const SizedBox(height: Spacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: ButtonComponent(
              variant: ButtonComponentVariant.link,
              label: context.strings.forgotPasswordPrompt,
              size: ButtonComponentSize.small,
              onTap: () async {
                await UserService.instance.sendOtt(
                  context,
                  email!,
                  isResetPasswordScreen: true,
                  isForgotPassword: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _returnToEmailEntry() {
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> verifyPassword(BuildContext context, String password) async {
    setState(() {
      _isPasswordIncorrect = false;
    });
    final dialog = createProgressDialog(
      context,
      context.strings.pleaseWait,
      isDismissible: true,
    );
    await dialog.show();
    try {
      if (!context.mounted) {
        await dialog.hide();
        return;
      }
      await UserService.instance.verifyEmailViaPassword(
        context,
        widget.srpAttributes,
        password,
        dialog,
      );
      if (mounted) TextInput.finishAutofillContext();
    } on DioException catch (e, s) {
      await dialog.hide();
      if (e.response != null && e.response!.statusCode == 401) {
        _logger.severe('server reject, failed verify SRP login', e, s);
        if (!mounted || !context.mounted) return;
        setState(() {
          _isPasswordIncorrect = true;
        });
      } else {
        _logger.severe('API failure during SRP login ${e.type}', e, s);
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout) {
          if (!context.mounted) return;
          await _showContactSupportDialog(
            context,
            context.strings.noInternetConnection,
            context.strings.pleaseCheckYourInternetConnectionAndTryAgain,
          );
        } else {
          if (!context.mounted) return;
          await _showContactSupportDialog(
            context,
            context.strings.somethingWentWrong,
            context.strings.verificationFailedPleaseTryAgain,
          );
        }
      }
    } catch (e, s) {
      _logger.info('error during loginViaPassword', e);
      await dialog.hide();
      if (e is LoginKeyDerivationError) {
        _logger.severe('loginKey derivation error', e, s);
        if (!context.mounted) return;
        await UserService.instance.sendOtt(
          context,
          email!,
          isCreateAccountScreen: true,
          onChangeEmail: _returnToEmailEntry,
        );
        return;
      } else if (e is KeyDerivationError) {
        // This device is not powerful enough to derive the key.
        if (!context.mounted) return;
        final dialogChoice = await showChoiceDialog(
          context,
          title: context.strings.recreatePasswordTitle,
          body: context.strings.recreatePasswordBody,
          firstButtonLabel: context.strings.useRecoveryKey,
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
          context.strings.oops,
          context.strings.verificationFailedPleaseTryAgain,
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
      firstButtonLabel: context.strings.contactSupport,
      secondButtonLabel: context.strings.ok,
    );
    if (dialogChoice?.action == ButtonAction.first && context.mounted) {
      await sendLogs(
        context,
        context.strings.contactSupport,
        "support@ente.com",
        postShare: () {},
      );
    }
  }
}
