import "package:email_validator/email_validator.dart";
import 'package:ente_accounts/ente_accounts.dart';
import 'package:ente_accounts/models/errors.dart';
import 'package:ente_configuration/base_configuration.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:ente_ui/components/buttons/dynamic_fab.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:ente_utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:logging/logging.dart';
import "package:styled_text/tags/styled_text_tag_action.dart";
import "package:styled_text/widgets/styled_text.dart";

class LoginPage extends StatefulWidget {
  final BaseConfiguration config;

  const LoginPage(this.config, {super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _emailIsValid = false;
  String? _email;
  Color? _emailInputFieldColor;
  final Logger _logger = Logger('_LoginPageState');

  Future<void> onPressed() async {
    await UserService.instance.setEmail(_email!);
    widget.config.resetVolatilePassword();
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
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return LoginPasswordVerificationPage(widget.config, attr!);
            },
          ),
        );
      }
    } else {
      await UserService.instance.sendOtt(
        mounted ? context : null,
        _email!,
        isCreateAccountScreen: false,
        purpose: 'login',
      );
    }
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void initState() {
    _email = widget.config.getEmail();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final isKeypadOpen = MediaQuery.of(context).viewInsets.bottom > 100;
    final colorScheme = getEnteColorScheme(context);

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
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: _getBody(),
      floatingActionButton: DynamicFAB(
        isKeypadOpen: isKeypadOpen,
        isFormValid: _emailIsValid,
        buttonText: context.strings.logInLabel,
        onPressedFunction: onPressed,
      ),
      floatingActionButtonLocation: fabLocation(),
      floatingActionButtonAnimator: NoScalingAnimation(),
    );
  }

  Widget _getBody() {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Column(
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
                        autofillHints: const [AutofillHints.email],
                        onFieldSubmitted: _emailIsValid
                            ? (value) => onPressed()
                            : null,
                        decoration: InputDecoration(
                          fillColor:
                              _emailInputFieldColor ?? colorScheme.backdropBase,
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
                        style: textTheme.body.copyWith(
                          color: colorScheme.textBase,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _email = value.trim();
                            _emailIsValid = EmailValidator.validate(_email!);
                            if (_emailIsValid) {
                              _emailInputFieldColor = getEnteColorScheme(
                                context,
                              ).primary700.withValues(alpha: 0.2);
                            } else {
                              _emailInputFieldColor = null;
                            }
                          });
                        },
                        autocorrect: false,
                        keyboardType: TextInputType.emailAddress,
                        //initialValue: _email,
                        autofocus: true,
                      ),
                      const SizedBox(height: 24),
                      StyledText(
                        text: context.strings.loginTerms,
                        style: textTheme.small.copyWith(
                          color: colorScheme.textMuted,
                        ),
                        tags: {
                          'u-terms': StyledTextActionTag(
                            (String? text, Map<String?, String?> attrs) =>
                                PlatformUtil.openWebView(
                                  context,
                                  context.strings.termsOfServicesTitle,
                                  "https://ente.com/terms",
                                ),
                            style: TextStyle(
                              decoration: TextDecoration.underline,
                              color: colorScheme.textMuted,
                            ),
                          ),
                          'u-policy': StyledTextActionTag(
                            (String? text, Map<String?, String?> attrs) =>
                                PlatformUtil.openWebView(
                                  context,
                                  context.strings.privacyPolicyTitle,
                                  "https://ente.com/privacy",
                                ),
                            style: TextStyle(
                              decoration: TextDecoration.underline,
                              color: colorScheme.textMuted,
                            ),
                          ),
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
