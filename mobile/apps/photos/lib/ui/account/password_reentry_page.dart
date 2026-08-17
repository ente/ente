import 'dart:async';
import "dart:typed_data";

import "package:ente_components/ente_components.dart";
import "package:ente_crypto/ente_crypto.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/subscription_purchased_event.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
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
  String? email;
  String? _volatilePassword;

  @override
  void initState() {
    super.initState();
    email = Configuration.instance.getEmail();
    _volatilePassword = Configuration.instance.getVolatilePassword();
    if (_volatilePassword != null) {
      _passwordController.text = _volatilePassword!;
      Future.delayed(Duration.zero, () => verifyPassword(_volatilePassword!));
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final isFormValid = _passwordController.text.isNotEmpty;

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
        title: Text(
          context.strings.enterPassword,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        centerTitle: true,
      ),
      body: _getBody(),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ButtonComponent(
          key: const ValueKey("verifyPasswordButton"),
          label: context.strings.logInLabel,
          isDisabled: !isFormValid,
          onTap: isFormValid ? _onVerifyPasswordPressed : null,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Future<void> _onVerifyPasswordPressed() async {
    if (_passwordController.text.isEmpty) {
      return;
    }
    FocusScope.of(context).unfocus();
    await verifyPassword(_passwordController.text);
  }

  Future<void> verifyPassword(String password) async {
    FocusScope.of(context).unfocus();
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
    } catch (e) {
      _logger.warning("Password verification failed: $e");
      await dialog.hide();
      if (!mounted) return;
      final dialogChoice = await showChoiceDialog(
        context,
        title: context.strings.incorrectPasswordTitle,
        body: context.strings.pleaseTryAgain,
        firstButtonLabel: context.strings.contactSupport,
        secondButtonLabel: context.strings.ok,
      );
      if (dialogChoice?.action == ButtonAction.first) {
        if (!mounted) return;
        await sendLogs(
          context,
          context.strings.contactSupport,
          "support@ente.com",
          postShare: () {},
        );
      }
      return;
    }
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
    return SafeArea(
      child: AutofillGroup(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
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
                isPasswordInput: true,
                autocorrect: false,
                shouldUnfocusOnClearOrSubmit: true,
                onSubmit: _passwordController.text.isNotEmpty
                    ? (_) => _onVerifyPasswordPressed()
                    : null,
                onChanged: (value) {
                  setState(() {});
                },
              ),
              const SizedBox(height: 16),
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
                    label: context.strings.forgotPassword,
                    size: ButtonComponentSize.small,
                    onTap: () async {
                      // ignore: unawaited_futures
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (BuildContext context) {
                            return const RecoveryPage();
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
