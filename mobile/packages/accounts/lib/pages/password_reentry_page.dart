import 'dart:async';
import 'dart:typed_data';

import 'package:ente_accounts/ente_accounts.dart';
import 'package:ente_accounts/models/errors.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_strings/ente_strings.dart';
import "package:ente_ui/components/alert_bottom_sheet.dart";
import 'package:ente_ui/components/buttons/dynamic_fab.dart';
import "package:ente_ui/components/buttons/gradient_button.dart";
import 'package:ente_ui/pages/base_home_page.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import 'package:ente_utils/email_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:logging/logging.dart';

class PasswordReentryPage extends StatefulWidget {
  final BaseConfiguration config;
  final BaseHomePage homePage;

  const PasswordReentryPage(this.config, this.homePage, {super.key});

  @override
  State<PasswordReentryPage> createState() => _PasswordReentryPageState();
}

class _PasswordReentryPageState extends State<PasswordReentryPage> {
  final _logger = Logger((_PasswordReentryPageState).toString());
  final _passwordController = TextEditingController();
  String? email;
  bool _passwordVisible = false;
  String? _volatilePassword;

  @override
  void initState() {
    super.initState();
    email = widget.config.getEmail();
    _volatilePassword = widget.config.getVolatilePassword();
    if (_volatilePassword != null) {
      _passwordController.text = _volatilePassword!;
      Future.delayed(
        Duration.zero,
        () => verifyPassword(_volatilePassword!, usingVolatilePassword: true),
      );
    }
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
        onPressedFunction: () async {
          FocusScope.of(context).unfocus();
          await verifyPassword(_passwordController.text);
        },
      ),
      floatingActionButtonLocation: fabLocation(),
      floatingActionButtonAnimator: NoScalingAnimation(),
    );
  }

  Future<void> verifyPassword(
    String password, {
    bool usingVolatilePassword = false,
  }) async {
    FocusScope.of(context).unfocus();
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();
    if (usingVolatilePassword) {
      _logger.info("Using volatile password");
    }
    try {
      final kek = await widget.config.decryptSecretsAndGetKeyEncKey(
        password,
        widget.config.getKeyAttributes()!,
      );
      unawaited(UserService.instance.autoAttributePendingSource());
      _registerSRPForExistingUsers(kek).ignore();
    } on KeyDerivationError catch (e, s) {
      _logger.severe("Password verification failed", e, s);
      await dialog.hide();
      if (!mounted) {
        return;
      }

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
      if (result == true && mounted) {
        // ignore: unawaited_futures
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return RecoveryPage(widget.config, widget.homePage);
            },
          ),
        );
      }
      return;
    } catch (e, s) {
      _logger.severe("Password verification failed", e, s);
      await dialog.hide();
      if (!mounted) {
        return;
      }

      final result = await showAlertBottomSheet<bool>(
        context,
        title: context.strings.incorrectPasswordTitle,
        message: context.strings.pleaseTryAgain,
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
      if (result == true && mounted) {
        await sendLogs(context, "support@ente.com", postShare: () {});
      }
      return;
    }
    widget.config.resetVolatilePassword();
    await dialog.hide();
    if (mounted) {
      unawaited(
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return widget.homePage;
            },
          ),
          (route) => false,
        ),
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
                          suffixIcon: IconButton(
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
                          ),
                        ),
                        style: textTheme.body.copyWith(
                          color: colorScheme.textBase,
                        ),
                        controller: _passwordController,
                        autofocus: true,
                        autocorrect: false,
                        obscureText: !_passwordVisible,
                        keyboardType: TextInputType.visiblePassword,
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
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (BuildContext context) {
                                    return RecoveryPage(
                                      widget.config,
                                      widget.homePage,
                                    );
                                  },
                                ),
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
