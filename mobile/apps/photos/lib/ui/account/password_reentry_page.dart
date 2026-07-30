import 'dart:async';
import "dart:typed_data";

import "package:ente_components/ente_components.dart";
import "package:ente_crypto/ente_crypto.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/subscription_purchased_event.dart';
import "package:photos/generated/l10n.dart";
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
          AppLocalizations.of(context).enterPassword,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        centerTitle: true,
      ),
      body: _getBody(),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ButtonComponent(
          key: const ValueKey("verifyPasswordButton"),
          label: AppLocalizations.of(context).logInLabel,
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
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).pleaseWait,
    );
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
        title: AppLocalizations.of(context).recreatePasswordTitle,
        body: AppLocalizations.of(context).recreatePasswordBody,
        firstButtonLabel: AppLocalizations.of(context).useRecoveryKey,
      );
      if (dialogChoice!.action == ButtonAction.first) {
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
    } catch (e, s) {
      _logger.severe("Password verification failed", e, s);
      await dialog.hide();
      if (!mounted) return;
      final dialogChoice = await showChoiceDialog(
        context,
        title: AppLocalizations.of(context).incorrectPasswordTitle,
        body: AppLocalizations.of(context).pleaseTryAgain,
        firstButtonLabel: AppLocalizations.of(context).contactSupport,
        secondButtonLabel: AppLocalizations.of(context).ok,
      );
      if (dialogChoice!.action == ButtonAction.first) {
        if (!mounted) return;
        await sendLogs(
          context,
          AppLocalizations.of(context).contactSupport,
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
              TextInputComponent(
                key: const ValueKey("passwordInputField"),
                label: AppLocalizations.of(context).password,
                isRequired: true,
                hintText: AppLocalizations.of(context).enterYourPassword,
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
                    label: AppLocalizations.of(context).changeEmail,
                    size: ButtonComponentSize.small,
                    onTap: () async {
                      final dialog = createProgressDialog(
                        context,
                        AppLocalizations.of(context).pleaseWait,
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
                    label: AppLocalizations.of(context).forgotPassword,
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
