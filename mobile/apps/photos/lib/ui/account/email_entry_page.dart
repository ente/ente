import 'dart:async';

import 'package:email_validator/email_validator.dart';
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:password_strength/password_strength.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/service_locator.dart";
import 'package:photos/services/account/user_service.dart';
import "package:photos/ui/account/login_page.dart";
import "package:photos/ui/account/onboarding_page_scaffold.dart";
import 'package:photos/ui/common/web_page.dart';
import "package:styled_text/styled_text.dart";

class EmailEntryPage extends StatefulWidget {
  const EmailEntryPage({
    super.key,
    this.showReferralSourceField = true,
    this.referralSource,
  });

  final bool showReferralSourceField;
  final String? referralSource;

  @override
  State<EmailEntryPage> createState() => _EmailEntryPageState();
}

class _EmailEntryPageState extends State<EmailEntryPage> {
  static const kMildPasswordStrengthThreshold = 0.4;
  static const kStrongPasswordStrengthThreshold = 0.7;

  final _config = Configuration.instance;
  final _emailController = TextEditingController();
  final _passwordController1 = TextEditingController();
  final _passwordController2 = TextEditingController();

  String? _email;
  String? _password;
  String _cnfPassword = '';
  String _referralSource = '';
  double _passwordStrength = 0.0;
  bool _emailIsValid = false;
  bool _showEmailValidation = false;
  bool _hasAgreedToTOS = false;
  bool _hasInstallSource = false;
  bool _passwordsMatch = false;
  bool _passwordIsValid = false;
  bool _showPasswordStrength = false;
  bool _showConfirmPasswordValidation = false;
  Timer? _emailValidationTimer;
  Timer? _passwordStrengthTimer;
  Timer? _confirmPasswordTimer;

  @override
  void initState() {
    super.initState();
    _referralSource = widget.referralSource?.trim() ?? '';
    if (widget.showReferralSourceField) {
      unawaited(_updateReferralSourceFieldVisibility());
    }
    final storedEmail = _config.getEmail();
    if (storedEmail != null && storedEmail.isNotEmpty) {
      _email = storedEmail;
      _emailController.text = storedEmail;
      _emailIsValid = EmailValidator.validate(storedEmail);
    }
  }

  @override
  void dispose() {
    _emailValidationTimer?.cancel();
    _passwordStrengthTimer?.cancel();
    _confirmPasswordTimer?.cancel();
    _emailController.dispose();
    _passwordController1.dispose();
    _passwordController2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingPageScaffold(
      title: context.strings.createAccountTitle,
      illustration: OnboardingIllustration.signUp,
      headerHeight: OnboardingPageScaffold.compactHeaderHeight,
      showDeveloperSettingsTapArea: true,
      body: _getBody(),
      actions: [
        ButtonComponent(
          key: const ValueKey("createAccountButton"),
          label: context.strings.createAccountTitle,
          shouldShowSuccessState: false,
          isDisabled: !_isFormValid(),
          onTap: _isFormValid() ? _submitCreateAccount : null,
        ),
        OnboardingAccountPrompt(
          question: context.strings.alreadyHaveAnAccount,
          actionLabel: context.strings.logInLabel,
          onTap: () async {
            FocusScope.of(context).unfocus();
            await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const LoginPage()));
          },
        ),
      ],
    );
  }

  Widget _getBody() {
    String? passwordMessage;
    TextInputComponentMessageType passwordMessageType =
        TextInputComponentMessageType.helper;

    if (_password != null && _password!.isNotEmpty && _showPasswordStrength) {
      if (_passwordStrength > kStrongPasswordStrengthThreshold) {
        passwordMessage = context.strings.strongPassword;
        passwordMessageType = TextInputComponentMessageType.success;
      } else if (_passwordStrength > kMildPasswordStrengthThreshold) {
        passwordMessage = context.strings.moderateStrength;
        passwordMessageType = TextInputComponentMessageType.alert;
      } else {
        passwordMessage = context.strings.weakStrength;
        passwordMessageType = TextInputComponentMessageType.alert;
      }
    }

    String? confirmPasswordMessage;
    TextInputComponentMessageType confirmPasswordMessageType =
        TextInputComponentMessageType.helper;

    if (_cnfPassword.isNotEmpty &&
        _password != null &&
        _password!.isNotEmpty &&
        _showConfirmPasswordValidation) {
      if (_passwordsMatch) {
        confirmPasswordMessage = context.strings.passwordsMatch;
        confirmPasswordMessageType = TextInputComponentMessageType.success;
      } else {
        confirmPasswordMessage = context.strings.passwordsDontMatch;
        confirmPasswordMessageType = TextInputComponentMessageType.alert;
      }
    }

    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextInputComponent(
            label: context.strings.email,
            hintText: context.strings.emailHint,
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            isRequired: true,
            onChanged: _onEmailChanged,
            message: _showEmailValidation
                ? _emailIsValid
                      ? context.strings.validEmailAddress
                      : context.strings.invalidEmailAddress
                : null,
            messageType: !_showEmailValidation
                ? TextInputComponentMessageType.helper
                : _emailIsValid
                ? TextInputComponentMessageType.success
                : TextInputComponentMessageType.alert,
          ),
          const SizedBox(height: Spacing.xl),
          TextInputComponent(
            label: context.strings.password,
            hintText: context.strings.enterYourPassword,
            controller: _passwordController1,
            isPasswordInput: true,
            isRequired: true,
            autocorrect: false,
            autofillHints: const [AutofillHints.newPassword],
            message: passwordMessage,
            messageType: passwordMessageType,
            onChanged: (password) {
              if (password != _password) {
                _passwordStrengthTimer?.cancel();
                setState(() {
                  _password = password;
                  _passwordStrength = estimatePasswordStrength(password);
                  _passwordIsValid =
                      _passwordStrength >= kMildPasswordStrengthThreshold;
                  _passwordsMatch = _password == _cnfPassword;
                  _showPasswordStrength = false;
                });
                _passwordStrengthTimer = Timer(const Duration(seconds: 1), () {
                  if (mounted) {
                    setState(() {
                      _showPasswordStrength = true;
                    });
                  }
                });
              }
            },
          ),
          const SizedBox(height: Spacing.xl),
          TextInputComponent(
            label: context.strings.confirmPassword,
            hintText: context.strings.reEnterPassword,
            controller: _passwordController2,
            isPasswordInput: true,
            isRequired: true,
            autocorrect: false,
            autofillHints: const [],
            finishAutofillContextOnEditingComplete: true,
            shouldUnfocusOnClearOrSubmit: true,
            onSubmit: _isFormValid() ? (_) => _submitCreateAccount() : null,
            message: confirmPasswordMessage,
            messageType: confirmPasswordMessageType,
            onChanged: (cnfPassword) {
              _confirmPasswordTimer?.cancel();
              setState(() {
                _cnfPassword = cnfPassword;
                _showConfirmPasswordValidation = false;
                if (_password != null && _password!.isNotEmpty) {
                  _passwordsMatch = _password == _cnfPassword;
                }
              });
              _confirmPasswordTimer = Timer(const Duration(seconds: 1), () {
                if (mounted) {
                  setState(() {
                    _showConfirmPasswordValidation = true;
                  });
                }
              });
            },
          ),
          if (_showReferralSourceField) ...[
            const SizedBox(height: Spacing.xl),
            TextInputComponent(
              label: context.strings.hearUsWhereTitle,
              autocorrect: false,
              shouldUnfocusOnClearOrSubmit: true,
              onSubmit: _isFormValid() ? (_) => _submitCreateAccount() : null,
              onChanged: (value) {
                _referralSource = value.trim();
              },
            ),
          ],
          const SizedBox(height: Spacing.xl),
          _getTOSAgreement(),
        ],
      ),
    );
  }

  bool get _showReferralSourceField =>
      widget.showReferralSourceField && !_hasInstallSource;

  String get _routeSource => widget.referralSource?.trim() ?? '';

  Future<void> _submitCreateAccount() async {
    if (!_isFormValid()) {
      return;
    }
    _config.setVolatilePassword(_passwordController1.text);
    await UserService.instance.setEmail(_email!);
    await UserService.instance.setRefSource(
      await _referralSourceForSubmission(),
    );
    if (!mounted) return;
    await UserService.instance.sendOtt(
      context,
      _email!,
      isCreateAccountScreen: true,
      purpose: "signup",
    );
  }

  Future<void> _updateReferralSourceFieldVisibility() async {
    final hasInstallSource = await installSourceService.hasInstallSource();
    _setHasInstallSource(hasInstallSource);
  }

  Future<String> _referralSourceForSubmission() async {
    if (!widget.showReferralSourceField) {
      return _routeSource;
    }
    if (_hasInstallSource) {
      return _routeSource;
    }
    final hasInstallSource = await installSourceService.hasInstallSource();
    _setHasInstallSource(hasInstallSource);
    return hasInstallSource ? _routeSource : _referralSource;
  }

  void _setHasInstallSource(bool hasInstallSource) {
    if (mounted && hasInstallSource != _hasInstallSource) {
      setState(() {
        _hasInstallSource = hasInstallSource;
      });
    }
  }

  void _onEmailChanged(String value) {
    final trimmed = value.trim();
    if (trimmed == _email) return;
    _emailValidationTimer?.cancel();

    final isValid = EmailValidator.validate(trimmed);

    setState(() {
      _email = trimmed;
      _emailIsValid = isValid;
      _showEmailValidation = false;
    });

    if (trimmed.isNotEmpty) {
      _emailValidationTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _showEmailValidation = true;
          });
        }
      });
    }
  }

  Widget _getTOSAgreement() {
    final colors = context.componentColors;
    return GestureDetector(
      onTap: () {
        setState(() {
          _hasAgreedToTOS = !_hasAgreedToTOS;
        });
      },
      behavior: HitTestBehavior.translucent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: CheckboxComponent(
              selected: _hasAgreedToTOS,
              onChanged: (value) {
                setState(() {
                  _hasAgreedToTOS = value;
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StyledText(
              text: context.strings.signUpTerms,
              style: TextStyles.body.copyWith(color: colors.textLighter),
              tags: {
                'u-terms': StyledTextActionTag(
                  (String? text, Map<String?, String?> attrs) =>
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (BuildContext context) {
                            return WebPage(
                              context.strings.termsOfServicesTitle,
                              "https://ente.com/terms",
                            );
                          },
                        ),
                      ),
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationColor: colors.textLighter,
                    color: colors.textLighter,
                  ),
                ),
                'u-policy': StyledTextActionTag(
                  (String? text, Map<String?, String?> attrs) =>
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (BuildContext context) {
                            return WebPage(
                              context.strings.privacyPolicyTitle,
                              "https://ente.com/privacy",
                            );
                          },
                        ),
                      ),
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationColor: colors.textLighter,
                    color: colors.textLighter,
                  ),
                ),
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _isFormValid() {
    return _emailIsValid &&
        _passwordsMatch &&
        _hasAgreedToTOS &&
        _passwordIsValid;
  }
}
