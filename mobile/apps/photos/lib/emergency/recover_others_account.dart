import "dart:async";

import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:password_strength/password_strength.dart';
import "package:photos/emergency/model.dart";
import "package:photos/services/authenticated_session.dart";
import "package:photos/services/legacy.dart" as legacy;
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/theme/text_style.dart";
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import "package:photos/ui/components/models/text_input_type_v2.dart";
import "package:photos/ui/components/text_input_widget_v2.dart";
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/utils/dialog_util.dart';

class RecoverOthersAccount extends StatefulWidget {
  final LegacyRecoverySession session;

  const RecoverOthersAccount({required this.session, super.key});

  @override
  State<RecoverOthersAccount> createState() => _RecoverOthersAccountState();
}

class _RecoverOthersAccountState extends State<RecoverOthersAccount> {
  static const kMildPasswordStrengthThreshold = 0.4;
  static const kStrongPasswordStrengthThreshold = 0.7;

  final _logger = Logger((_RecoverOthersAccountState).toString());
  final _passwordController1 = TextEditingController();
  final _passwordController2 = TextEditingController();
  String _passwordInInputBox = '';
  String _passwordInInputConfirmationBox = '';
  double _passwordStrength = 0.0;

  bool _passwordsMatch = false;
  bool _isPasswordValid = false;
  bool _showPasswordStrength = false;
  Timer? _passwordStrengthTimer;

  @override
  void dispose() {
    _passwordStrengthTimer?.cancel();
    _passwordController1.dispose();
    _passwordController2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final title = context.strings.resetPasswordTitle;
    final isFormValid = _passwordsMatch && _isPasswordValid;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: colorScheme.backgroundColour,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.backgroundColour,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: colorScheme.content,
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: Text(title, style: textTheme.largeBold),
        centerTitle: true,
      ),
      body: _getBody(colorScheme, textTheme),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ButtonWidgetV2(
          buttonType: ButtonTypeV2.primary,
          labelText: title,
          isDisabled: !isFormValid,
          onTap: isFormValid
              ? () async {
                  await _updatePassword();
                  if (!context.mounted) return;
                  FocusScope.of(context).unfocus();
                }
              : null,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _getBody(EnteColorScheme colorScheme, EnteTextTheme textTheme) {
    final email = widget.session.user.email;
    String? passwordMessage;
    TextInputMessageType passwordMessageType = TextInputMessageType.guide;

    if (_passwordInInputBox.isNotEmpty && _showPasswordStrength) {
      if (_passwordStrength > kStrongPasswordStrengthThreshold) {
        passwordMessage = context.strings.strongPassword;
        passwordMessageType = TextInputMessageType.success;
      } else if (_passwordStrength <= kMildPasswordStrengthThreshold) {
        passwordMessage = context.strings.weakStrength;
        passwordMessageType = TextInputMessageType.alert;
      }
    }

    String? confirmPasswordMessage;
    TextInputMessageType confirmPasswordMessageType =
        TextInputMessageType.guide;

    if (_passwordInInputConfirmationBox.isNotEmpty &&
        _passwordInInputBox.isNotEmpty) {
      if (_passwordsMatch) {
        confirmPasswordMessage = context.strings.passwordsMatch;
        confirmPasswordMessageType = TextInputMessageType.success;
      } else {
        confirmPasswordMessage = context.strings.passwordsDontMatch;
        confirmPasswordMessageType = TextInputMessageType.error;
      }
    }

    return SafeArea(
      child: AutofillGroup(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView(
            children: [
              const SizedBox(height: 16),
              Text(
                "Enter new password for $email account. You will be able "
                "to use this password to login into $email account.",
                style: textTheme.body.copyWith(color: colorScheme.textMuted),
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
              TextInputWidgetV2(
                label: context.strings.password,
                hintText: context.strings.password,
                textEditingController: _passwordController1,
                isPasswordInput: true,
                isRequired: true,
                autoCorrect: false,
                autofillHints: const [AutofillHints.newPassword],
                message: passwordMessage,
                messageType: passwordMessageType,
                onChange: (password) {
                  if (password != _passwordInInputBox) {
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
                  }
                },
              ),
              const SizedBox(height: 16),
              TextInputWidgetV2(
                label: context.strings.confirmPassword,
                hintText: context.strings.confirmPassword,
                textEditingController: _passwordController2,
                isPasswordInput: true,
                isRequired: true,
                autoCorrect: false,
                autofillHints: const [AutofillHints.newPassword],
                finishAutofillContextOnEditingComplete: true,
                message: confirmPasswordMessage,
                messageType: confirmPasswordMessageType,
                onChange: (confirmPassword) {
                  setState(() {
                    _passwordInInputConfirmationBox = confirmPassword;
                    if (_passwordInInputBox.isNotEmpty) {
                      _passwordsMatch =
                          _passwordInInputBox ==
                          _passwordInInputConfirmationBox;
                    }
                  });
                },
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updatePassword() async {
    final dialog = createProgressDialog(
      context,
      context.strings.generatingEncryptionKeys,
    );
    await dialog.show();
    try {
      await legacy.changePassword(
        session: authenticatedSession(),
        recoveryId: widget.session.id,
        newPassword: _passwordController1.text,
      );
      await dialog.hide();
      if (!mounted) return;
      showShortToast(context, context.strings.passwordChangedSuccessfully);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e, s) {
      _logger.severe("Failed to recover account", e, s);
      await dialog.hide();
      if (!mounted) return;
      showGenericErrorBottomSheet(context: context, error: e).ignore();
    }
  }
}
