import 'dart:async';

import 'package:email_validator/email_validator.dart';
import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import 'package:password_strength/password_strength.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import 'package:photos/services/account/user_service.dart';
import "package:photos/ui/account/login_page.dart";
import 'package:photos/ui/common/web_page.dart';
import "package:photos/ui/settings/developer_settings_tap_area.dart";
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
  bool _hasAgreedToTOS = true;
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
            AppLocalizations.of(context).createAccountTitle,
            style: TextStyles.large.copyWith(color: colors.textBase),
          ),
        ),
        centerTitle: true,
      ),
      body: _getBody(),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ButtonComponent(
          key: const ValueKey("createAccountButton"),
          label: AppLocalizations.of(context).createAccountTitle,
          isDisabled: !_isFormValid(),
          onTap: _isFormValid() ? _submitCreateAccount : null,
        ),
      ),
      bottomNavigationBar: isKeyboardOpen ? null : _getLoginPrompt(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _getBody() {
    String? passwordMessage;
    TextInputComponentMessageType passwordMessageType =
        TextInputComponentMessageType.helper;

    if (_password != null && _password!.isNotEmpty && _showPasswordStrength) {
      if (_passwordStrength > kStrongPasswordStrengthThreshold) {
        passwordMessage = AppLocalizations.of(context).strongPassword;
        passwordMessageType = TextInputComponentMessageType.success;
      } else if (_passwordStrength <= kMildPasswordStrengthThreshold) {
        passwordMessage = AppLocalizations.of(context).weakStrength;
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
        confirmPasswordMessage = AppLocalizations.of(context).passwordsMatch;
        confirmPasswordMessageType = TextInputComponentMessageType.success;
      } else {
        confirmPasswordMessage = AppLocalizations.of(
          context,
        ).passwordsDontMatch;
        confirmPasswordMessageType = TextInputComponentMessageType.error;
      }
    }

    return AutofillGroup(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  TextInputComponent(
                    label: AppLocalizations.of(context).email,
                    hintText: AppLocalizations.of(context).email,
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    isRequired: true,
                    onChanged: _onEmailChanged,
                    message: _showEmailValidation && !_emailIsValid
                        ? AppLocalizations.of(context).invalidEmailAddress
                        : null,
                    messageType: _showEmailValidation && !_emailIsValid
                        ? TextInputComponentMessageType.alert
                        : TextInputComponentMessageType.helper,
                  ),
                  const SizedBox(height: 24),
                  TextInputComponent(
                    label: AppLocalizations.of(context).password,
                    hintText: AppLocalizations.of(context).password,
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
                          _passwordStrength = estimatePasswordStrength(
                            password,
                          );
                          _passwordIsValid =
                              _passwordStrength >=
                              kMildPasswordStrengthThreshold;
                          _passwordsMatch = _password == _cnfPassword;
                          _showPasswordStrength = false;
                        });
                        _passwordStrengthTimer = Timer(
                          const Duration(seconds: 1),
                          () {
                            if (mounted) {
                              setState(() {
                                _showPasswordStrength = true;
                              });
                            }
                          },
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  TextInputComponent(
                    label: AppLocalizations.of(context).confirmPassword,
                    hintText: AppLocalizations.of(context).confirmPassword,
                    controller: _passwordController2,
                    isPasswordInput: true,
                    isRequired: true,
                    autocorrect: false,
                    autofillHints: const [],
                    finishAutofillContextOnEditingComplete: true,
                    shouldUnfocusOnClearOrSubmit: true,
                    onSubmit: _isFormValid()
                        ? (_) => _submitCreateAccount()
                        : null,
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
                      _confirmPasswordTimer = Timer(
                        const Duration(seconds: 1),
                        () {
                          if (mounted) {
                            setState(() {
                              _showConfirmPasswordValidation = true;
                            });
                          }
                        },
                      );
                    },
                  ),
                  if (_showReferralSourceField) ...[
                    const SizedBox(height: 24),
                    TextInputComponent(
                      label: AppLocalizations.of(context).hearUsWhereTitle,
                      autocorrect: false,
                      shouldUnfocusOnClearOrSubmit: true,
                      onSubmit: _isFormValid()
                          ? (_) => _submitCreateAccount()
                          : null,
                      onChanged: (value) {
                        _referralSource = value.trim();
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  _getTOSAgreement(),
                ],
              ),
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                children: [
                  Expanded(child: DeveloperSettingsTapArea()),
                  SizedBox(height: 80),
                ],
              ),
            ),
          ),
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
    if (!mounted) return;
    FocusScope.of(context).unfocus();
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

  Widget _getLoginPrompt() {
    final colors = context.componentColors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppLocalizations.of(context).alreadyHaveAnAccount,
              style: TextStyles.body.copyWith(color: colors.textLight),
            ),
            const SizedBox(width: 4),
            ButtonComponent(
              label: AppLocalizations.of(context).logInLabel,
              variant: ButtonComponentVariant.link,
              size: ButtonComponentSize.small,
              shouldSurfaceExecutionStates: false,
              onTap: _goToLoginPage,
            ),
          ],
        ),
      ),
    );
  }

  void _onEmailChanged(String value) {
    _emailValidationTimer?.cancel();

    final trimmed = value.trim();
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
        children: [
          Checkbox(
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return colors.primary;
              }
              return null;
            }),
            value: _hasAgreedToTOS,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            side: CheckboxTheme.of(context).side,
            visualDensity: VisualDensity.compact,
            onChanged: (value) {
              setState(() {
                _hasAgreedToTOS = value!;
              });
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StyledText(
              text: AppLocalizations.of(context).signUpTerms,
              style: TextStyles.mini.copyWith(color: colors.textLight),
              tags: {
                'u-terms': StyledTextActionTag(
                  (String? text, Map<String?, String?> attrs) =>
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (BuildContext context) {
                            return WebPage(
                              AppLocalizations.of(context).termsOfServicesTitle,
                              "https://ente.com/terms",
                            );
                          },
                        ),
                      ),
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    color: colors.textLight,
                  ),
                ),
                'u-policy': StyledTextActionTag(
                  (String? text, Map<String?, String?> attrs) =>
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (BuildContext context) {
                            return WebPage(
                              AppLocalizations.of(context).privacyPolicyTitle,
                              "https://ente.com/privacy",
                            );
                          },
                        ),
                      ),
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    color: colors.textLight,
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

  Future<void> _goToLoginPage() async {
    FocusScope.of(context).unfocus();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LoginPage()));
  }
}
