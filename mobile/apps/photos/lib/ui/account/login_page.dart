import 'dart:async';

import 'package:email_validator/email_validator.dart';
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:logging/logging.dart";
import 'package:photos/core/configuration.dart';
import "package:photos/core/errors.dart";
import "package:photos/gateways/users/models/srp.dart";
import 'package:photos/services/account/user_service.dart';
import "package:photos/ui/account/email_entry_page.dart";
import "package:photos/ui/account/login_pwd_verification_page.dart";
import "package:photos/ui/account/onboarding_page_scaffold.dart";

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  bool _emailIsValid = false;
  bool _isSubmitting = false;
  bool _showValidationMessage = false;
  String? _email;
  Timer? _validationTimer;
  final _config = Configuration.instance;
  final Logger _logger = Logger('_LoginPageState');

  @override
  void initState() {
    super.initState();
    if ((_config.getEmail() ?? '').isNotEmpty) {
      _updateEmail(_config.getEmail()!);
    } else if (kDebugMode) {
      _updateEmail(const String.fromEnvironment("email"));
    }
  }

  void _updateEmail(String value) {
    if (value.isEmpty) return;
    _email = value.trim();
    _emailController.text = _email!;
    _emailIsValid = EmailValidator.validate(_email!);
  }

  @override
  void dispose() {
    _validationTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingPageScaffold(
      title: context.strings.loginToEnte,
      illustration: OnboardingIllustration.login,
      showDeveloperSettingsTapArea: true,
      body: _getBody(),
      actions: [
        TextFieldTapRegion(
          groupId: _emailController,
          child: ButtonComponent(
            key: const ValueKey("logInButton"),
            label: context.strings.continueLabel,
            shouldShowSuccessState: false,
            isDisabled: !_emailIsValid,
            onTap: _emailIsValid ? _submitLoginEmail : null,
          ),
        ),
        OnboardingAccountPrompt(
          question: context.strings.dontHaveAnAccount,
          actionLabel: context.strings.signUp,
          onTap: () async {
            FocusScope.of(context).unfocus();
            await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const EmailEntryPage()));
          },
        ),
      ],
    );
  }

  Widget _getBody() {
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextInputComponent(
            key: const ValueKey("emailInputField"),
            label: context.strings.email,
            hintText: context.strings.emailHint,
            controller: _emailController,
            groupId: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            autofocus: true,
            isRequired: true,
            onSubmit: (_) => _submitLoginEmail(),
            onChanged: _onEmailChanged,
            message: _showValidationMessage
                ? _emailIsValid
                      ? context.strings.validEmailAddress
                      : context.strings.invalidEmailAddress
                : null,
            messageType: !_showValidationMessage
                ? TextInputComponentMessageType.helper
                : _emailIsValid
                ? TextInputComponentMessageType.success
                : TextInputComponentMessageType.alert,
          ),
        ],
      ),
    );
  }

  void _onEmailChanged(String value) {
    final trimmed = value.trim();
    if (trimmed == _email) return;
    _validationTimer?.cancel();

    final isValid = EmailValidator.validate(trimmed);

    setState(() {
      _email = trimmed;
      _emailIsValid = isValid;
      _showValidationMessage = false;
    });

    if (trimmed.isNotEmpty) {
      _validationTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _showValidationMessage = true;
          });
        }
      });
    }
  }

  Future<void> _submitLoginEmail() async {
    if (_isSubmitting) return;
    final trimmed = _emailController.text.trim();
    final isValid = EmailValidator.validate(trimmed);
    if (!isValid) {
      setState(() {
        _email = trimmed;
        _emailIsValid = false;
        _showValidationMessage = true;
      });
      return;
    }
    _email = trimmed;
    _isSubmitting = true;
    try {
      await _onLoginPressed(trimmed);
    } finally {
      _isSubmitting = false;
    }
  }

  Future<void> _onLoginPressed(String email) async {
    await UserService.instance.setEmail(email);
    Configuration.instance.resetVolatilePassword();
    SrpAttributes? attr;
    bool isEmailVerificationEnabled = true;
    try {
      attr = await UserService.instance.getSrpAttributes(email);
      isEmailVerificationEnabled = attr.isEmailMFAEnabled;
    } catch (e) {
      if (e is! SrpSetupNotCompleteError) {
        _logger.severe('Error getting SRP attributes', e);
      }
    }
    if (attr != null && !isEmailVerificationEnabled) {
      if (!mounted) return;
      // ignore: unawaited_futures
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return LoginPasswordVerificationPage(srpAttributes: attr!);
          },
        ),
      );
    } else {
      if (!mounted) return;
      await UserService.instance.sendOtt(
        context,
        email,
        isCreateAccountScreen: false,
        purpose: "login",
      );
    }
  }
}
