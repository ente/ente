import 'dart:async';

import 'package:email_validator/email_validator.dart';
import "package:ente_components/ente_components.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:logging/logging.dart";
import 'package:photos/core/configuration.dart';
import "package:photos/core/errors.dart";
import "package:photos/gateways/users/models/srp.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/services/account/user_service.dart';
import "package:photos/ui/account/email_entry_page.dart";
import "package:photos/ui/account/login_pwd_verification_page.dart";
import "package:photos/ui/settings/developer_settings_tap_area.dart";

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  bool _emailIsValid = false;
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
    final colors = context.componentColors;
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
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
        title: DeveloperSettingsTapArea(
          behavior: HitTestBehavior.translucent,
          child: Text(
            AppLocalizations.of(context).loginToEnte,
            style: TextStyles.large.copyWith(color: colors.textBase),
          ),
        ),
        centerTitle: true,
      ),
      body: _getBody(),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ButtonComponent(
          key: const ValueKey("logInButton"),
          label: AppLocalizations.of(context).continueLabel,
          isDisabled: !_emailIsValid,
          onTap: _emailIsValid ? _submitLoginEmail : null,
        ),
      ),
      bottomNavigationBar: isKeyboardOpen ? null : _getSignUpPrompt(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _getBody() {
    return AutofillGroup(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            TextInputComponent(
              key: const ValueKey("emailInputField"),
              label: AppLocalizations.of(context).email,
              hintText: AppLocalizations.of(context).enterYourEmailAddress,
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              autofocus: true,
              isRequired: true,
              shouldUnfocusOnClearOrSubmit: true,
              onSubmit: (_) => _submitLoginEmail(),
              onChanged: _onEmailChanged,
              message: _showValidationMessage && !_emailIsValid
                  ? AppLocalizations.of(context).invalidEmailAddress
                  : null,
              messageType: _showValidationMessage && !_emailIsValid
                  ? TextInputComponentMessageType.alert
                  : TextInputComponentMessageType.helper,
            ),
            const SizedBox(height: 24),
            const Expanded(child: DeveloperSettingsTapArea()),
          ],
        ),
      ),
    );
  }

  Widget _getSignUpPrompt() {
    final colors = context.componentColors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppLocalizations.of(context).dontHaveAnAccount,
              style: TextStyles.body.copyWith(color: colors.textLight),
            ),
            const SizedBox(width: 4),

            ButtonComponent(
              label: AppLocalizations.of(context).signUp,
              variant: ButtonComponentVariant.link,
              size: ButtonComponentSize.small,
              shouldSurfaceExecutionStates: false,
              onTap: _goToSignUpPage,
            ),
          ],
        ),
      ),
    );
  }

  void _onEmailChanged(String value) {
    _validationTimer?.cancel();

    final trimmed = value.trim();
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
    await _onLoginPressed();
  }

  Future<void> _onLoginPressed() async {
    await UserService.instance.setEmail(_email!);
    Configuration.instance.resetVolatilePassword();
    SrpAttributes? attr;
    bool isEmailVerificationEnabled = true;
    try {
      attr = await UserService.instance.getSrpAttributes(_email!);
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
        _email!,
        isCreateAccountScreen: false,
        purpose: "login",
      );
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
  }

  Future<void> _goToSignUpPage() async {
    FocusScope.of(context).unfocus();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const EmailEntryPage()));
  }
}
