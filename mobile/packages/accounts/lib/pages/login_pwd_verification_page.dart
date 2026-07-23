import "package:dio/dio.dart";
import "package:ente_accounts/ente_accounts.dart";
import "package:ente_configuration/base_configuration.dart";
import "package:ente_crypto_api/ente_crypto_api.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/alert_bottom_sheet.dart";
import "package:ente_ui/components/buttons/dynamic_fab.dart";
import "package:ente_ui/components/buttons/gradient_button.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:ente_ui/utils/dialog_util.dart";
import "package:ente_utils/email_util.dart";
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import "package:logging/logging.dart";

// LoginPasswordVerificationPage is a page that allows the user to enter their password to verify their identity.
// If the password is correct, then the user is either directed to
// PasswordReentryPage (if the user has not yet set up 2FA) or TwoFactorAuthenticationPage (if the user has set up 2FA).
// In the PasswordReentryPage, the password is auto-filled based on the
// volatile password.
class LoginPasswordVerificationPage extends StatefulWidget {
  final BaseConfiguration config;
  final SrpAttributes srpAttributes;
  const LoginPasswordVerificationPage(
    this.config,
    this.srpAttributes, {
    super.key,
  });

  @override
  State<LoginPasswordVerificationPage> createState() =>
      _LoginPasswordVerificationPageState();
}

class _LoginPasswordVerificationPageState
    extends State<LoginPasswordVerificationPage> {
  final _logger = Logger((_LoginPasswordVerificationPageState).toString());
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  String? email;
  bool _passwordVisible = false;
  bool _passwordInFocus = false;

  Future<void> onPressed() async {
    FocusScope.of(context).unfocus();
    await verifyPassword(context, _passwordController.text);
  }

  @override
  void initState() {
    super.initState();
    email = widget.config.getEmail();
    _passwordFocusNode.addListener(() {
      setState(() {
        _passwordInFocus = _passwordFocusNode.hasFocus;
      });
    });
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
        key: const ValueKey("verifyPasswordButton"),
        isKeypadOpen: isKeypadOpen,
        isFormValid: _passwordController.text.isNotEmpty,
        buttonText: context.strings.logInLabel,
        onPressedFunction: onPressed,
      ),
      floatingActionButtonLocation: fabLocation(),
      floatingActionButtonAnimator: NoScalingAnimation(),
    );
  }

  Future<void> verifyPassword(BuildContext context, String password) async {
    final dialog = createProgressDialog(
      context,
      context.strings.pleaseWait,
      isDismissible: true,
    );
    await dialog.show();
    try {
      await UserService.instance.verifyEmailViaPassword(
        context.mounted ? context : null,
        widget.srpAttributes,
        password,
        dialog,
      );
    } on DioException catch (e, s) {
      await dialog.hide();
      if (!context.mounted) {
        return;
      }

      if (e.response != null && e.response!.statusCode == 401) {
        _logger.severe('server reject, failed verify SRP login', e, s);
        await _showContactSupportDialog(
          context,
          title: context.strings.incorrectPasswordTitle,
          message: context.strings.pleaseTryAgain,
        );
      } else {
        _logger.severe('API failure during SRP login', e, s);
        if (e.type == DioExceptionType.connectionError) {
          await _showContactSupportDialog(
            context,
            title: context.strings.noInternetConnection,
            message:
                context.strings.pleaseCheckYourInternetConnectionAndTryAgain,
          );
        } else {
          await _showContactSupportDialog(
            context,
            title: context.strings.oops,
            message: context.strings.verificationFailedPleaseTryAgain,
          );
        }
      }
    } catch (e, s) {
      _logger.info('error during loginViaPassword', e);
      await dialog.hide();
      if (e is LoginKeyDerivationError) {
        _logger.severe('loginKey derivation error', e, s);
        // LoginKey err, perform regular login via ott verification
        await UserService.instance.sendOtt(
          context.mounted ? context : null,
          email!,
          isCreateAccountScreen: true,
        );
        return;
      } else if (e is KeyDerivationError) {
        if (!context.mounted) {
          return;
        }
        // device is not powerful enough to perform derive key
        final result = await showAlertBottomSheet<bool>(
          context,
          title: context.strings.recreatePasswordTitle,
          message: context.strings.recreatePasswordBody,
          assetPath: 'assets/warning-grey.png',
          buttons: [
            GradientButton(
              text: context.strings.useRecoveryKey,
              onTap: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
        if (result == true) {
          await UserService.instance.sendOtt(
            context.mounted ? context : null,
            email!,
            isResetPasswordScreen: true,
          );
        }
        return;
      } else {
        _logger.severe('unexpected error while verifying password', e, s);
        if (context.mounted) {
          await _showContactSupportDialog(
            context,
            title: context.strings.oops,
            message: context.strings.verificationFailedPleaseTryAgain,
          );
        }
      }
    }
  }

  Future<void> _showContactSupportDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final result = await showAlertBottomSheet<bool>(
      context,
      title: title,
      message: message,
      assetPath: 'assets/warning-grey.png',
      buttons: [
        GradientButton(
          text: context.strings.contactSupport,
          onTap: () {
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );
    if (result == true && context.mounted) {
      await sendLogs(context, "support@ente.com", postShare: () {});
    }
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
                      Text.rich(
                        TextSpan(
                          text: "${context.strings.enterThePasswordFor} ",
                          style: textTheme.body.copyWith(
                            color: colorScheme.textMuted,
                          ),
                          children: [
                            TextSpan(
                              text: email,
                              style: textTheme.body.copyWith(
                                color: colorScheme.primary700,
                              ),
                            ),
                          ],
                        ),
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
                        onFieldSubmitted: _passwordController.text.isNotEmpty
                            ? (_) => onPressed()
                            : null,
                        key: const ValueKey("passwordInputField"),
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          fillColor: colorScheme.backdropBase,
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
                          suffixIcon: _passwordInFocus
                              ? IconButton(
                                  icon: Icon(
                                    _passwordVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: colorScheme.textMuted,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _passwordVisible = !_passwordVisible;
                                    });
                                  },
                                )
                              : null,
                        ),
                        style: textTheme.body.copyWith(
                          color: colorScheme.textBase,
                        ),
                        controller: _passwordController,
                        autofocus: true,
                        autocorrect: false,
                        obscureText: !_passwordVisible,
                        keyboardType: TextInputType.visiblePassword,
                        focusNode: _passwordFocusNode,
                        onChanged: (_) {
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              await UserService.instance.sendOtt(
                                context,
                                email!,
                                isResetPasswordScreen: true,
                              );
                            },
                            child: Text(
                              "${context.strings.forgotPassword}?",
                              style: textTheme.body.copyWith(
                                color: colorScheme.primary700,
                                decoration: TextDecoration.underline,
                                decorationColor: colorScheme.primary700,
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              final dialog = createProgressDialog(
                                context,
                                context.strings.pleaseWait,
                              );
                              await dialog.show();
                              await widget.config.logout();
                              await dialog.hide();
                              if (mounted) {
                                Navigator.of(
                                  context,
                                ).popUntil((route) => route.isFirst);
                              }
                            },
                            child: Text(
                              context.strings.changeEmail,
                              style: textTheme.body.copyWith(
                                color: colorScheme.primary700,
                                decoration: TextDecoration.underline,
                                decorationColor: colorScheme.primary700,
                              ),
                            ),
                          ),
                        ],
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
