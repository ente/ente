import 'package:ente_accounts/ente_accounts.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_strings/ente_strings.dart';
import "package:ente_ui/components/alert_bottom_sheet.dart";
import "package:ente_ui/components/base_bottom_sheet.dart";
import 'package:ente_ui/components/buttons/dynamic_fab.dart';
import "package:ente_ui/components/buttons/gradient_button.dart";
import 'package:ente_ui/pages/base_home_page.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:ente_utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:logging/logging.dart';
import 'package:password_strength/password_strength.dart';
import 'package:styled_text/styled_text.dart';

enum PasswordEntryMode { set, update, reset }

class PasswordEntryPage extends StatefulWidget {
  final BaseConfiguration config;
  final PasswordEntryMode mode;
  final BaseHomePage homePage;

  const PasswordEntryPage(this.config, this.mode, this.homePage, {super.key});

  @override
  State<PasswordEntryPage> createState() => _PasswordEntryPageState();
}

class _PasswordEntryPageState extends State<PasswordEntryPage> {
  static const kMildPasswordStrengthThreshold = 0.4;
  static const kStrongPasswordStrengthThreshold = 0.7;

  final _logger = Logger((_PasswordEntryPageState).toString());
  final _passwordController1 = TextEditingController(),
      _passwordController2 = TextEditingController();
  Color? _validFieldValueColor;
  String? _volatilePassword;
  String _passwordInInputBox = '';
  String _passwordInInputConfirmationBox = '';
  double _passwordStrength = 0.0;
  bool _password1Visible = false;
  bool _password2Visible = false;
  final _password1FocusNode = FocusNode();
  final _password2FocusNode = FocusNode();
  bool _password1InFocus = false;
  bool _password2InFocus = false;

  bool _passwordsMatch = false;
  bool _isPasswordValid = false;

  bool get _hasValidMatchingPasswords =>
      _isPasswordValid &&
      _passwordInInputBox.isNotEmpty &&
      _passwordInInputConfirmationBox.isNotEmpty &&
      _passwordInInputBox == _passwordInInputConfirmationBox;

  @override
  void initState() {
    super.initState();
    _volatilePassword = widget.config.getVolatilePassword();
    if (_volatilePassword != null) {
      Future.delayed(
        Duration.zero,
        () => _showRecoveryCodeDialog(
          _volatilePassword!,
          usingVolatilePassword: true,
        ),
      );
    }
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
  }

  @override
  Widget build(BuildContext context) {
    final isKeypadOpen = MediaQuery.of(context).viewInsets.bottom > 100;

    FloatingActionButtonLocation? fabLocation() {
      if (isKeypadOpen) {
        return null;
      } else {
        return FloatingActionButtonLocation.centerFloat;
      }
    }

    final colorScheme = getEnteColorScheme(context);
    _validFieldValueColor = colorScheme.primary700.withValues(alpha: 0.2);

    String title = context.strings.setPasswordTitle;
    if (widget.mode == PasswordEntryMode.update) {
      title = context.strings.changePasswordTitle;
    } else if (widget.mode == PasswordEntryMode.reset) {
      title = context.strings.resetPasswordTitle;
    } else if (_volatilePassword != null) {
      title = context.strings.encryptionKeys;
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
        leading: widget.mode == PasswordEntryMode.reset
            ? Container()
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                color: colorScheme.primary700,
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
      ),
      body: _getBody(title),
      floatingActionButton: DynamicFAB(
        isKeypadOpen: isKeypadOpen,
        isFormValid: _passwordsMatch && _isPasswordValid,
        buttonText: title,
        onPressedFunction: () {
          if (widget.mode == PasswordEntryMode.set) {
            _showRecoveryCodeDialog(_passwordController1.text);
          } else {
            _updatePassword();
          }
          FocusScope.of(context).unfocus();
        },
      ),
      floatingActionButtonLocation: fabLocation(),
      floatingActionButtonAnimator: NoScalingAnimation(),
    );
  }

  Widget _getBody(String title) {
    final email = widget.config.getEmail();
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

    if (_volatilePassword != null) {
      return Container();
    }
    return Column(
      children: [
        Expanded(
          child: AutofillGroup(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        Text(
                          title,
                          style: textTheme.h3Bold.copyWith(
                            color: colorScheme.textBase,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.mode == PasswordEntryMode.set
                              ? context.strings.enterPasswordToEncrypt
                              : context.strings.enterNewPasswordToEncrypt,
                          textAlign: TextAlign.start,
                          style: textTheme.small.copyWith(
                            color: colorScheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        StyledText(
                          text: context.strings.passwordWarning,
                          style: textTheme.small.copyWith(
                            color: colorScheme.textMuted,
                          ),
                          tags: {
                            'underline': StyledTextTag(
                              style: textTheme.small.copyWith(
                                color: colorScheme.textMuted,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          },
                        ),
                        const SizedBox(height: 24),
                        Text(
                          context.strings.password,
                          style: textTheme.bodyBold.copyWith(
                            color: colorScheme.textBase,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Visibility(
                          // hidden textForm for suggesting auto-fill service for saving
                          // password
                          visible: false,
                          child: TextFormField(
                            autofillHints: const [AutofillHints.email],
                            autocorrect: false,
                            keyboardType: TextInputType.emailAddress,
                            initialValue: email,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        TextFormField(
                          autofillHints: const [AutofillHints.newPassword],
                          onFieldSubmitted: (_) {
                            do {
                              FocusScope.of(context).nextFocus();
                            } while (FocusScope.of(
                                  context,
                                ).focusedChild!.context ==
                                null);
                          },
                          decoration: InputDecoration(
                            fillColor: _isPasswordValid
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
                                : _isPasswordValid
                                ? Icon(
                                    Icons.check,
                                    color: colorScheme.primary700,
                                  )
                                : null,
                          ),
                          style: textTheme.body.copyWith(
                            color: colorScheme.textBase,
                          ),
                          obscureText: !_password1Visible,
                          controller: _passwordController1,
                          autofocus: false,
                          autocorrect: false,
                          keyboardType: TextInputType.visiblePassword,
                          onChanged: (password) {
                            setState(() {
                              _passwordInInputBox = password;
                              _passwordStrength = estimatePasswordStrength(
                                password,
                              );
                              _isPasswordValid =
                                  _passwordStrength >=
                                  kMildPasswordStrengthThreshold;
                              _passwordsMatch = _hasValidMatchingPasswords;
                            });
                          },
                          textInputAction: TextInputAction.next,
                          focusNode: _password1FocusNode,
                        ),
                        Opacity(
                          opacity:
                              (_passwordInInputBox != '') && _password1InFocus
                              ? 1
                              : 0,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              context.strings.passwordStrength(
                                passwordStrengthText,
                              ),
                              style: TextStyle(color: passwordStrengthColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
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
                          decoration: InputDecoration(
                            fillColor: _passwordsMatch
                                ? _validFieldValueColor
                                : colorScheme.backdropBase,
                            filled: true,
                            hintText: context.strings.enterYourPasswordHint,
                            hintStyle: TextStyle(color: colorScheme.textMuted),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
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
                            border: OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          style: textTheme.body.copyWith(
                            color: colorScheme.textBase,
                          ),
                          focusNode: _password2FocusNode,
                          onChanged: (cnfPassword) {
                            setState(() {
                              _passwordInInputConfirmationBox = cnfPassword;
                              _passwordsMatch = _hasValidMatchingPasswords;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              PlatformUtil.openWebView(
                                context,
                                "${context.strings.howItWorks}?",
                                "https://ente.com/architecture",
                              );
                            },
                            child: Text(
                              "${context.strings.howItWorks}?",
                              style: textTheme.body.copyWith(
                                color: colorScheme.primary700,
                                decoration: TextDecoration.underline,
                                decorationColor: colorScheme.primary700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _updatePassword() async {
    final logOutFromOthers = await logOutFromOtherDevices(context);
    if (logOutFromOthers == null) {
      return;
    }
    final dialog = mounted
        ? createProgressDialog(
            context,
            context.strings.generatingEncryptionKeys,
          )
        : null;
    await dialog?.show();
    try {
      final result = await widget.config.getAttributesForNewPassword(
        _passwordController1.text,
      );
      await UserService.instance.updateKeyAttributes(
        result.item1,
        result.item2,
        logoutOtherDevices: logOutFromOthers,
      );
      await dialog?.hide();
      if (mounted) {
        showShortToast(context, context.strings.passwordChangedSuccessfully);
        Navigator.of(context).pop();
        if (widget.mode == PasswordEntryMode.reset) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } catch (e, s) {
      _logger.severe("Failed to change password", e, s);
      await dialog?.hide();
      if (mounted) {
        // ignore: unawaited_futures
        showGenericErrorDialog(context: context, error: e);
      }
    }
  }

  Future<bool?> logOutFromOtherDevices(BuildContext context) async {
    bool? logOutFromOther;

    await showBaseBottomSheet(
      context,
      headerSpacing: 20,
      title: context.strings.signOutFromOtherDevices,
      isDismissible: false,
      enableDrag: false,
      showCloseButton: true,
      child: Builder(
        builder: (bottomSheetContext) {
          final colorScheme = getEnteColorScheme(bottomSheetContext);
          final textTheme = getEnteTextTheme(bottomSheetContext);
          return Column(
            children: [
              Text(
                context.strings.signOutOtherBody,
                style: textTheme.body.copyWith(color: colorScheme.textMuted),
              ),
              const SizedBox(height: 20),
              GradientButton(
                text: context.strings.doNotSignOut,
                onTap: () {
                  logOutFromOther = false;
                  Navigator.of(bottomSheetContext).pop();
                },
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  logOutFromOther = true;
                  Navigator.of(bottomSheetContext).pop();
                },
                child: Text(
                  context.strings.signOutOtherDevices,
                  style: textTheme.bodyBold.copyWith(
                    color: colorScheme.warning400,
                    decoration: TextDecoration.underline,
                    decorationColor: colorScheme.warning400,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return logOutFromOther;
  }

  Future<void> _showRecoveryCodeDialog(
    String password, {
    bool usingVolatilePassword = false,
  }) async {
    final dialog = createProgressDialog(
      context,
      context.strings.generatingEncryptionKeysTitle,
    );
    await dialog.show();
    try {
      if (usingVolatilePassword) {
        _logger.info('Using volatile password');
      }
      final result = await widget.config.generateKey(password);
      widget.config.resetVolatilePassword();
      await dialog.hide();
      if (!mounted) {
        return;
      }
      onDone() async {
        final dialog = mounted
            ? createProgressDialog(context, context.strings.pleaseWait)
            : null;
        await dialog?.show();
        try {
          await UserService.instance.setAttributes(result);
          await dialog?.hide();
          widget.config.resetVolatilePassword();
          if (mounted) {
            // ignore: unawaited_futures
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (BuildContext context) {
                  return widget.homePage;
                },
              ),
              (route) => false,
            );
          }
        } catch (e, s) {
          _logger.severe("Failed to configure account", e, s);
          await dialog?.hide();
          if (mounted) {
            // ignore: unawaited_futures
            showGenericErrorDialog(context: context, error: e);
          }
        }
      }

      // ignore: unawaited_futures
      routeToPage(
        context,
        RecoveryKeyPage(
          widget.config,
          result.privateKeyAttributes.recoveryKey,
          context.strings.continueLabel,
          showAppBar: false,
          isDismissible: false,
          onDone: onDone,
          showProgressBar: true,
        ),
      );
    } catch (e) {
      _logger.severe(e);
      await dialog.hide();
      if (!mounted) {
        return;
      }
      if (e is UnsupportedError) {
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: context.strings.insecureDevice,
          message: context
              .strings
              .sorryWeCouldNotGenerateSecureKeysOnThisDevicennplease,
          assetPath: 'assets/warning-grey.png',
        );
      } else {
        // ignore: unawaited_futures
        showGenericErrorDialog(context: context, error: e);
      }
    }
  }
}
