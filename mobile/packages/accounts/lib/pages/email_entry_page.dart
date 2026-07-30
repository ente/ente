import 'package:dots_indicator/dots_indicator.dart';
import 'package:email_validator/email_validator.dart';
import 'package:ente_accounts/ente_accounts.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/buttons/dynamic_fab.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:ente_utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:password_strength/password_strength.dart';
import "package:styled_text/styled_text.dart";

class EmailEntryPage extends StatefulWidget {
  final BaseConfiguration config;

  const EmailEntryPage(this.config, {super.key});

  @override
  State<EmailEntryPage> createState() => _EmailEntryPageState();
}

class _EmailEntryPageState extends State<EmailEntryPage> {
  static const kMildPasswordStrengthThreshold = 0.4;
  static const kStrongPasswordStrengthThreshold = 0.7;

  final _passwordController1 = TextEditingController();
  final _passwordController2 = TextEditingController();
  Color? _validFieldValueColor;

  String? _email;
  String? _password;
  String _cnfPassword = '';
  String _referralSource = '';
  double _passwordStrength = 0.0;
  bool _emailIsValid = false;
  bool _hasAgreedToTOS = true;
  bool _password1Visible = false;
  bool _password2Visible = false;
  bool _passwordsMatch = false;
  bool _hasInstallSource = false;

  final _password1FocusNode = FocusNode();
  final _password2FocusNode = FocusNode();
  bool _password1InFocus = false;
  bool _password2InFocus = false;
  bool _passwordIsValid = false;

  bool get _hasValidMatchingPasswords =>
      _passwordIsValid &&
      (_password?.isNotEmpty ?? false) &&
      _cnfPassword.isNotEmpty &&
      _password == _cnfPassword;

  @override
  void initState() {
    _email = widget.config.getEmail();
    _password1FocusNode.addListener(() {
      setState(() {
        _password1InFocus = _password1FocusNode.hasFocus;
      });
    });
    _password2FocusNode.addListener(() {
      setState(() {
        _password2InFocus = _password2FocusNode.hasFocus;
      });
    });
    super.initState();
    _updateReferralSourceFieldVisibility();
  }

  @override
  Widget build(BuildContext context) {
    final isKeypadOpen = MediaQuery.of(context).viewInsets.bottom > 100;

    // Initialize theme-aware color
    final colorScheme = getEnteColorScheme(context);
    _validFieldValueColor = colorScheme.primary700.withValues(alpha: 0.2);

    FloatingActionButtonLocation? fabLocation() {
      if (isKeypadOpen) {
        return null;
      } else {
        return FloatingActionButtonLocation.centerFloat;
      }
    }

    return Scaffold(
      resizeToAvoidBottomInset: isKeypadOpen,
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
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _getBody(),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isKeypadOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: DotsIndicator(
                dotsCount: 3,
                position: 0,
                decorator: DotsDecorator(
                  activeColor: colorScheme.primary700,
                  color: colorScheme.primary700.withValues(alpha: 0.32),
                  activeShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  size: const Size(10, 10),
                  activeSize: const Size(20, 10),
                  spacing: const EdgeInsets.all(6),
                ),
              ),
            ),
          DynamicFAB(
            isKeypadOpen: isKeypadOpen,
            isFormValid: _isFormValid(),
            buttonText: context.strings.createAccount,
            onPressedFunction: () async {
              await UserService.instance.setEmail(_email!);
              widget.config.setVolatilePassword(_passwordController1.text);
              await UserService.instance.setRefSource(
                await _referralSourceForSubmission(),
              );
              await UserService.instance.sendOtt(
                context.mounted ? context : null,
                _email!,
                isCreateAccountScreen: true,
                purpose: "signup",
              );
              if (context.mounted) {
                FocusScope.of(context).unfocus();
              }
            },
          ),
        ],
      ),
      floatingActionButtonLocation: fabLocation(),
      floatingActionButtonAnimator: NoScalingAnimation(),
    );
  }

  Widget _getBody() {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    var passwordStrengthText = context.strings.weakStrength;
    var passwordStrengthColor = Colors.redAccent;
    if (_passwordStrength > kStrongPasswordStrengthThreshold) {
      passwordStrengthText = context.strings.strongStrength;
      passwordStrengthColor = Colors.greenAccent;
    } else if (_passwordStrength > kMildPasswordStrengthThreshold) {
      passwordStrengthText = context.strings.moderateStrength;
      passwordStrengthColor = Colors.orangeAccent;
    }
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: AutofillGroup(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        Text(
                          context.strings.email,
                          style: textTheme.bodyBold.copyWith(
                            color: colorScheme.textBase,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          style: textTheme.body.copyWith(
                            color: colorScheme.textBase,
                          ),
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(
                            fillColor: _emailIsValid
                                ? _validFieldValueColor
                                : colorScheme.backdropBase,
                            filled: true,
                            hintText: context.strings.emailHint,
                            hintStyle: TextStyle(color: colorScheme.textMuted),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixIcon: _emailIsValid
                                ? Icon(
                                    Icons.check,
                                    size: 20,
                                    color: colorScheme.primary700,
                                  )
                                : null,
                          ),
                          onChanged: (value) {
                            _email = value.trim();
                            if (_emailIsValid !=
                                EmailValidator.validate(_email!)) {
                              setState(() {
                                _emailIsValid = EmailValidator.validate(
                                  _email!,
                                );
                              });
                            }
                          },
                          autocorrect: false,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.strings.password,
                          style: textTheme.bodyBold.copyWith(
                            color: colorScheme.textBase,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          controller: _passwordController1,
                          obscureText: !_password1Visible,
                          enableSuggestions: true,
                          autofillHints: const [AutofillHints.newPassword],
                          style: textTheme.body.copyWith(
                            color: colorScheme.textBase,
                          ),
                          decoration: InputDecoration(
                            fillColor: _passwordIsValid
                                ? _validFieldValueColor
                                : colorScheme.backdropBase,
                            filled: true,
                            hintText: context.strings.enterYourPasswordHint,
                            hintStyle: TextStyle(color: colorScheme.textMuted),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixIcon: _password1InFocus
                                ? IconButton(
                                    icon: Icon(
                                      _password1Visible
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                      color: colorScheme.textMuted,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _password1Visible = !_password1Visible;
                                      });
                                    },
                                  )
                                : _passwordIsValid
                                ? Icon(
                                    Icons.check,
                                    color: colorScheme.primary700,
                                  )
                                : null,
                          ),
                          focusNode: _password1FocusNode,
                          onChanged: (password) {
                            if (password != _password) {
                              setState(() {
                                _password = password;
                                _passwordStrength = estimatePasswordStrength(
                                  password,
                                );
                                _passwordIsValid =
                                    _passwordStrength >=
                                    kMildPasswordStrengthThreshold;
                                _passwordsMatch = _hasValidMatchingPasswords;
                              });
                            }
                          },
                          onEditingComplete: () {
                            _password1FocusNode.unfocus();
                            _password2FocusNode.requestFocus();
                            TextInput.finishAutofillContext();
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.strings.confirmPassword,
                          style: textTheme.bodyBold.copyWith(
                            color: colorScheme.textBase,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          keyboardType: TextInputType.visiblePassword,
                          controller: _passwordController2,
                          obscureText: !_password2Visible,
                          autofillHints: const [AutofillHints.newPassword],
                          onEditingComplete: () =>
                              TextInput.finishAutofillContext(),
                          style: textTheme.body.copyWith(
                            color: colorScheme.textBase,
                          ),
                          decoration: InputDecoration(
                            fillColor: _passwordsMatch && _passwordIsValid
                                ? _validFieldValueColor
                                : colorScheme.backdropBase,
                            filled: true,
                            hintText: context.strings.reEnterPassword,
                            hintStyle: TextStyle(color: colorScheme.textMuted),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixIcon: _password2InFocus
                                ? IconButton(
                                    icon: Icon(
                                      _password2Visible
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                      color: colorScheme.textMuted,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _password2Visible = !_password2Visible;
                                      });
                                    },
                                  )
                                : _passwordsMatch
                                ? Icon(
                                    Icons.check,
                                    color: colorScheme.primary700,
                                  )
                                : null,
                          ),
                          focusNode: _password2FocusNode,
                          onChanged: (cnfPassword) {
                            setState(() {
                              _cnfPassword = cnfPassword;
                              _passwordsMatch = _hasValidMatchingPasswords;
                            });
                          },
                        ),
                        Opacity(
                          opacity: (_password != '') && _password1InFocus
                              ? 1
                              : 0,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              context.strings.passwordStrength(
                                passwordStrengthText,
                              ),
                              style: TextStyle(
                                color: passwordStrengthColor,
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        if (_showReferralSourceField) const SizedBox(height: 8),
                        if (_showReferralSourceField)
                          Text(
                            context.strings.hearUsWhereTitle,
                            style: textTheme.bodyBold.copyWith(
                              color: colorScheme.textBase,
                            ),
                          ),
                        if (_showReferralSourceField) const SizedBox(height: 8),
                        if (_showReferralSourceField)
                          TextFormField(
                            style: textTheme.body.copyWith(
                              color: colorScheme.textBase,
                            ),
                            decoration: InputDecoration(
                              fillColor: colorScheme.backdropBase,
                              filled: true,
                              hintStyle: TextStyle(
                                color: colorScheme.textMuted,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderSide: BorderSide.none,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide.none,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onChanged: (value) {
                              _referralSource = value.trim();
                            },
                            autocorrect: false,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.next,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _getTOSAgreement(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _showReferralSourceField => !_hasInstallSource;

  Future<void> _updateReferralSourceFieldVisibility() async {
    final hasInstallSource = await UserService.instance.hasInstallSource();
    _setHasInstallSource(hasInstallSource);
  }

  Future<String> _referralSourceForSubmission() async {
    if (_hasInstallSource) {
      return '';
    }
    final hasInstallSource = await UserService.instance.hasInstallSource();
    _setHasInstallSource(hasInstallSource);
    return hasInstallSource ? '' : _referralSource;
  }

  void _setHasInstallSource(bool hasInstallSource) {
    if (mounted && hasInstallSource != _hasInstallSource) {
      setState(() {
        _hasInstallSource = hasInstallSource;
      });
    }
  }

  Widget _getTOSAgreement() {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);

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
            value: _hasAgreedToTOS,
            side: CheckboxTheme.of(context).side,
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return colorScheme.primary700;
              }
              return Colors.transparent;
            }),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            onChanged: (value) {
              setState(() {
                _hasAgreedToTOS = value!;
              });
            },
          ),
          Expanded(
            child: StyledText(
              text: context.strings.signUpTerms,
              style: textTheme.small.copyWith(color: colorScheme.textMuted),
              tags: {
                'u-terms': StyledTextActionTag(
                  (String? text, Map<String?, String?> attrs) =>
                      PlatformUtil.openWebView(
                        context,
                        context.strings.termsOfServicesTitle,
                        "https://ente.com/terms",
                      ),
                  style: const TextStyle(decoration: TextDecoration.underline),
                ),
                'u-policy': StyledTextActionTag(
                  (String? text, Map<String?, String?> attrs) =>
                      PlatformUtil.openWebView(
                        context,
                        context.strings.privacyPolicyTitle,
                        "https://ente.com/privacy",
                      ),
                  style: const TextStyle(decoration: TextDecoration.underline),
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
