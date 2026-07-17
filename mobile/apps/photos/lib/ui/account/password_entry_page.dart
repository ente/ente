import "dart:async";

import "package:ente_components/ente_components.dart";
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:password_strength/password_strength.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/account_configured_event.dart';
import 'package:photos/events/subscription_purchased_event.dart';
import "package:photos/gateways/users/models/key_gen_result.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import 'package:photos/services/account/user_service.dart';
import 'package:photos/ui/account/recovery_key_page.dart';
import 'package:photos/ui/common/web_page.dart';
import "package:photos/ui/components/alert_bottom_sheet.dart";
import "package:photos/ui/components/models/button_type.dart";
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/payment/subscription.dart';
import 'package:photos/utils/dialog_util.dart';
import "package:styled_text/styled_text.dart";

enum PasswordEntryMode { set, update, reset }

class PasswordEntryPage extends StatefulWidget {
  final PasswordEntryMode mode;

  const PasswordEntryPage({required this.mode, super.key});

  @override
  State<PasswordEntryPage> createState() => _PasswordEntryPageState();
}

class _PasswordEntryPageState extends State<PasswordEntryPage> {
  static const kMildPasswordStrengthThreshold = 0.4;
  static const kStrongPasswordStrengthThreshold = 0.7;

  final _logger = Logger((_PasswordEntryPageState).toString());
  final _passwordController1 = TextEditingController();
  final _passwordController2 = TextEditingController();
  String? _volatilePassword;
  String _passwordInInputBox = '';
  String _passwordInInputConfirmationBox = '';
  double _passwordStrength = 0.0;

  bool _passwordsMatch = false;
  bool _isPasswordValid = false;
  bool _showPasswordStrength = false;
  bool _showConfirmPasswordValidation = false;
  Timer? _passwordStrengthTimer;
  Timer? _confirmPasswordTimer;

  @override
  void initState() {
    super.initState();
    _volatilePassword = Configuration.instance.getVolatilePassword();
    if (_volatilePassword != null) {
      Future.delayed(
        Duration.zero,
        () => _showRecoveryCodeDialog(_volatilePassword!),
      );
    }
  }

  @override
  void dispose() {
    _passwordStrengthTimer?.cancel();
    _confirmPasswordTimer?.cancel();
    _passwordController1.dispose();
    _passwordController2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    String title = AppLocalizations.of(context).setPasswordTitle;
    if (widget.mode == PasswordEntryMode.update) {
      title = AppLocalizations.of(context).changePasswordTitle;
    } else if (widget.mode == PasswordEntryMode.reset) {
      title = AppLocalizations.of(context).resetPasswordTitle;
    } else if (_volatilePassword != null) {
      title = AppLocalizations.of(context).encryptionKeys;
    }

    final isFormValid = _passwordsMatch && _isPasswordValid;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.backgroundBase,
        leading: widget.mode == PasswordEntryMode.reset
            ? const SizedBox.shrink()
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                color: colors.iconColor,
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
        title: Text(
          title,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        centerTitle: true,
      ),
      body: _volatilePassword != null
          ? const SizedBox.shrink()
          : _getBody(title: title, isFormValid: isFormValid),
    );
  }

  Future<void> _submitPassword() async {
    if (!_passwordsMatch || !_isPasswordValid) {
      return;
    }
    if (widget.mode == PasswordEntryMode.set) {
      await _showRecoveryCodeDialog(_passwordController1.text);
    } else {
      _updatePassword();
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
  }

  Widget _getBody({required String title, required bool isFormValid}) {
    final colors = context.componentColors;
    final email = Configuration.instance.getEmail();

    String? passwordMessage;
    TextInputComponentMessageType passwordMessageType =
        TextInputComponentMessageType.helper;

    if (_passwordInInputBox.isNotEmpty && _showPasswordStrength) {
      if (_passwordStrength > kStrongPasswordStrengthThreshold) {
        passwordMessage = AppLocalizations.of(context).strongPassword;
        passwordMessageType = TextInputComponentMessageType.success;
      } else if (_passwordStrength > kMildPasswordStrengthThreshold) {
        passwordMessage = AppLocalizations.of(context).moderateStrength;
        passwordMessageType = TextInputComponentMessageType.alert;
      } else {
        passwordMessage = AppLocalizations.of(context).weakStrength;
        passwordMessageType = TextInputComponentMessageType.alert;
      }
    }

    String? confirmPasswordMessage;
    TextInputComponentMessageType confirmPasswordMessageType =
        TextInputComponentMessageType.helper;

    if (_passwordInInputConfirmationBox.isNotEmpty &&
        _passwordInInputBox.isNotEmpty &&
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

    return SafeArea(
      child: SingleChildScrollView(
        child: AutofillGroup(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text(
                  widget.mode == PasswordEntryMode.set
                      ? AppLocalizations.of(context).enterPasswordToEncrypt
                      : AppLocalizations.of(context).enterNewPasswordToEncrypt,
                  style: TextStyles.body.copyWith(color: colors.textLight),
                ),
                const SizedBox(height: 8),
                StyledText(
                  text: AppLocalizations.of(context).passwordWarning,
                  style: TextStyles.body.copyWith(color: colors.textLight),
                  tags: {
                    'underline': StyledTextTag(
                      style: TextStyles.body.copyWith(
                        color: colors.textLight,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  },
                ),
                const SizedBox(height: 24),
                Visibility(
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
                    _passwordStrengthTimer?.cancel();
                    setState(() {
                      _passwordInInputBox = password;
                      _passwordStrength = estimatePasswordStrength(password);
                      _isPasswordValid =
                          _passwordStrength >= kMildPasswordStrengthThreshold;
                      _passwordsMatch =
                          _passwordInInputBox ==
                          _passwordInInputConfirmationBox;
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
                  },
                ),
                const SizedBox(height: 16),
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
                  onSubmit: _passwordsMatch && _isPasswordValid
                      ? (_) => _submitPassword()
                      : null,
                  message: confirmPasswordMessage,
                  messageType: confirmPasswordMessageType,
                  onChanged: (cnfPassword) {
                    _confirmPasswordTimer?.cancel();
                    setState(() {
                      _passwordInInputConfirmationBox = cnfPassword;
                      _showConfirmPasswordValidation = false;
                      if (_passwordInInputBox.isNotEmpty) {
                        _passwordsMatch =
                            _passwordInInputBox ==
                            _passwordInInputConfirmationBox;
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
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ButtonComponent(
                    variant: ButtonComponentVariant.link,
                    label: AppLocalizations.of(context).howItWorks,
                    size: ButtonComponentSize.small,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (BuildContext context) {
                            return WebPage(
                              AppLocalizations.of(context).howItWorks,
                              "https://ente.com/architecture",
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                ButtonComponent(
                  label: title,
                  isDisabled: !isFormValid,
                  onTap: isFormValid ? _submitPassword : null,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _updatePassword() async {
    final logOutFromOthers = await logOutFromOtherDevices(context);
    if (!mounted) return;
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).generatingEncryptionKeys,
    );
    await dialog.show();
    try {
      final result = await Configuration.instance.getAttributesForNewPassword(
        _passwordController1.text,
      );
      await UserService.instance.updateKeyAttributes(
        result.item1,
        result.item2,
        logoutOtherDevices: logOutFromOthers,
      );
      await dialog.hide();
      if (widget.mode == PasswordEntryMode.reset) {
        Bus.instance.fire(SubscriptionPurchasedEvent());
      }
      if (!mounted) return;
      showShortToast(
        context,
        AppLocalizations.of(context).passwordChangedSuccessfully,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (widget.mode == PasswordEntryMode.reset) {
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e, s) {
      _logger.severe("Failed to change password", e, s);
      await dialog.hide();
      if (!mounted) return;
      await showGenericErrorBottomSheet(context: context, error: e);
    }
  }

  Future<bool> logOutFromOtherDevices(BuildContext context) async {
    bool logOutFromOther = true;
    await showChoiceDialog(
      context,
      title: context.l10n.signOutFromOtherDevices,
      body: context.l10n.signOutOtherBody,
      isDismissible: false,
      firstButtonLabel: context.l10n.signOutOtherDevices,
      firstButtonType: ButtonType.critical,
      firstButtonOnTap: () async {
        logOutFromOther = true;
      },
      secondButtonLabel: context.l10n.doNotSignOut,
      secondButtonOnTap: () async {
        logOutFromOther = false;
      },
    );
    return logOutFromOther;
  }

  Future<void> _showRecoveryCodeDialog(String password) async {
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).generatingEncryptionKeys,
    );
    await dialog.show();
    try {
      final KeyGenResult result = await Configuration.instance.generateKey(
        password,
      );
      Configuration.instance.resetVolatilePassword();
      await dialog.hide();
      Future<void> onDone() async {
        final dialog = createProgressDialog(
          context,
          AppLocalizations.of(context).pleaseWait,
        );
        await dialog.show();
        try {
          await UserService.instance.setAttributes(result);
          await dialog.hide();
          Configuration.instance.resetVolatilePassword();
          if (mounted) {
            await Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (BuildContext context) {
                  return getSubscriptionPage(isOnBoarding: true);
                },
              ),
              (route) => route.isFirst,
            );
          }
          Bus.instance.fire(AccountConfiguredEvent());
        } catch (e, s) {
          _logger.severe("Failed to configure account", e, s);
          await dialog.hide();
          if (!mounted) return;
          await showGenericErrorBottomSheet(context: context, error: e);
        }
      }

      if (!mounted) return;
      // ignore: unawaited_futures
      routeToPage(
        context,
        RecoveryKeyPage(
          result.privateKeyAttributes.recoveryKey,
          AppLocalizations.of(context).continueLabel,
          onDone: onDone,
          isOnboarding: true,
        ),
      );
    } catch (e) {
      _logger.severe(e);
      await dialog.hide();
      if (!mounted) return;
      if (e is UnsupportedError) {
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: AppLocalizations.of(context).insecureDevice,
          message: AppLocalizations.of(
            context,
          ).sorryWeCouldNotGenerateSecureKeysOnThisDevicennplease,
          assetPath: 'assets/warning-grey.png',
        );
      } else {
        await showGenericErrorBottomSheet(context: context, error: e);
      }
    }
  }
}
