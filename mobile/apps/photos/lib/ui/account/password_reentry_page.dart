import 'dart:async';
import "dart:typed_data";

import "package:ente_components/ente_components.dart";
import "package:ente_crypto/ente_crypto.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import "package:flutter/services.dart" show TextInput;
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/subscription_purchased_event.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/ui/account/onboarding_page_scaffold.dart";
import 'package:photos/ui/account/recovery_page.dart';
import 'package:photos/ui/components/buttons/button_widget.dart'
    show ButtonAction;
import 'package:photos/ui/tabs/home_widget.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:photos/utils/email_util.dart';

class PasswordReentryPage extends StatefulWidget {
  const PasswordReentryPage({super.key});

  @override
  State<PasswordReentryPage> createState() => _PasswordReentryPageState();
}

class _PasswordReentryPageState extends State<PasswordReentryPage> {
  final _logger = Logger((_PasswordReentryPageState).toString());
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _isSubmitting = false;
  String? email;
  String? _volatilePassword;
  bool _isPasswordIncorrect = false;

  @override
  void initState() {
    super.initState();
    email = Configuration.instance.getEmail();
    _volatilePassword = Configuration.instance.getVolatilePassword();
    if (_volatilePassword != null) {
      _passwordController.text = _volatilePassword!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_onVerifyPasswordPressed());
      });
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
    final isFormValid = _passwordController.text.isNotEmpty;

    return OnboardingPageScaffold(
      title: context.strings.enterPassword,
      illustration: OnboardingIllustration.password,
      body: _getBody(),
      actions: [
        ButtonComponent(
          key: const ValueKey("verifyPasswordButton"),
          label: context.strings.logInLabel,
          shouldShowSuccessState: false,
          isDisabled: !isFormValid,
          onTap: isFormValid ? _onVerifyPasswordPressed : null,
        ),
      ],
    );
  }

  Future<void> _onVerifyPasswordPressed() async {
    if (_passwordController.text.isEmpty || _isSubmitting) {
      return;
    }
    _isSubmitting = true;
    try {
      await verifyPassword(_passwordController.text);
    } finally {
      _isSubmitting = false;
    }
  }

  Future<void> verifyPassword(String password) async {
    _passwordFocusNode.unfocus();
    setState(() {
      _isPasswordIncorrect = false;
    });
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    try {
      final kek = await Configuration.instance.decryptSecretsAndGetKeyEncKey(
        password,
        Configuration.instance.getKeyAttributes()!,
      );
      unawaited(installSourceService.autoAttributePendingSource());
      _registerSRPForExistingUsers(kek).ignore();
    } on KeyDerivationError catch (e, s) {
      _logger.severe("Password verification failed", e, s);
      await dialog.hide();
      if (!mounted) return;
      final dialogChoice = await showChoiceDialog(
        context,
        title: context.strings.recreatePasswordTitle,
        body: context.strings.recreatePasswordBody,
        firstButtonLabel: context.strings.useRecoveryKey,
      );
      if (dialogChoice?.action == ButtonAction.first) {
        if (!mounted) return;
        // ignore: unawaited_futures
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const RecoveryPage();
            },
          ),
        );
      }
      return;
    } on IncorrectPasswordError catch (e, s) {
      _logger.warning("Password verification failed", e, s);
      await dialog.hide();
      if (!mounted) return;
      setState(() {
        _isPasswordIncorrect = true;
      });
      return;
    } catch (e, s) {
      _logger.severe("Password verification failed", e, s);
      await dialog.hide();
      if (!mounted) return;
      await _showContactSupportDialog(
        context.strings.somethingWentWrong,
        context.strings.verificationFailedPleaseTryAgain,
      );
      return;
    }
    if (mounted) TextInput.finishAutofillContext();
    await dialog.hide();
    Configuration.instance.resetVolatilePassword();
    await flagService.tryRefreshFlags();
    Bus.instance.fire(SubscriptionPurchasedEvent());
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return const HomeWidget();
          },
        ),
        (route) => false,
      ),
    );
  }

  Future<void> _showContactSupportDialog(String title, String message) async {
    final dialogChoice = await showChoiceDialog(
      context,
      title: title,
      body: message,
      firstButtonLabel: context.strings.contactSupport,
      secondButtonLabel: context.strings.ok,
    );
    if (dialogChoice?.action == ButtonAction.first && mounted) {
      await sendLogs(
        context,
        context.strings.contactSupport,
        "support@ente.com",
        postShare: () {},
      );
    }
  }

  Future<void> _registerSRPForExistingUsers(Uint8List key) async {
    bool shouldSetupSRP = false;
    try {
      // ignore: unused_local_variable
      final attr = await UserService.instance.getSrpAttributes(email!);
    } on SrpSetupNotCompleteError {
      shouldSetupSRP = true;
    } catch (e, s) {
      _logger.severe("error while fetching attr", e, s);
    }
    if (shouldSetupSRP) {
      try {
        final Uint8List loginKey = await CryptoUtil.deriveLoginKey(key);
        await UserService.instance.registerOrUpdateSrp(loginKey);
      } catch (e, s) {
        _logger.severe("error while setting up srp for existing users", e, s);
      }
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
            // Give autofill the account email to pair with the password.
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
            isRequired: true,
            hintText: context.strings.enterYourPassword,
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            isPasswordInput: true,
            autocorrect: false,
            shouldUnfocusOnClearOrSubmit: true,
            onSubmit: _passwordController.text.isNotEmpty
                ? (_) => _onVerifyPasswordPressed()
                : null,
            message: _isPasswordIncorrect
                ? context.strings.incorrectPasswordTitle
                : null,
            messageType: _isPasswordIncorrect
                ? TextInputComponentMessageType.alert
                : TextInputComponentMessageType.helper,
            onChanged: (value) {
              setState(() {
                _isPasswordIncorrect = false;
              });
            },
          ),
          const SizedBox(height: Spacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ButtonComponent(
                variant: ButtonComponentVariant.link,
                label: context.strings.changeEmail,
                size: ButtonComponentSize.small,
                onTap: () async {
                  final dialog = createProgressDialog(
                    context,
                    context.strings.pleaseWait,
                  );
                  await dialog.show();
                  await Configuration.instance.logout();
                  await dialog.hide();
                  if (!mounted) return;
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
              ButtonComponent(
                variant: ButtonComponentVariant.link,
                label: context.strings.forgotPasswordPrompt,
                size: ButtonComponentSize.small,
                onTap: () async {
                  // ignore: unawaited_futures
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (BuildContext context) {
                        return const RecoveryPage(isForgotPassword: true);
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
