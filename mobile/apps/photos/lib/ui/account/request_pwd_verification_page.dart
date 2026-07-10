import "dart:convert";
import "dart:typed_data";

import "package:ente_components/ente_components.dart";
import "package:ente_crypto/ente_crypto.dart";
import 'package:flutter/material.dart';
import "package:logging/logging.dart";
import 'package:photos/core/configuration.dart';
import "package:photos/l10n/l10n.dart";
import "package:photos/ui/components/alert_bottom_sheet.dart";
import "package:photos/utils/dialog_util.dart";

typedef OnPasswordVerifiedFn = Future<void> Function(Uint8List bytes);

class RequestPasswordVerificationPage extends StatefulWidget {
  final OnPasswordVerifiedFn onPasswordVerified;
  final Function? onPasswordError;

  const RequestPasswordVerificationPage({
    super.key,
    required this.onPasswordVerified,
    this.onPasswordError,
  });

  @override
  State<RequestPasswordVerificationPage> createState() =>
      _RequestPasswordVerificationPageState();
}

class _RequestPasswordVerificationPageState
    extends State<RequestPasswordVerificationPage> {
  final _logger = Logger((_RequestPasswordVerificationPageState).toString());
  final _passwordController = TextEditingController();
  String? email;

  @override
  void initState() {
    super.initState();
    email = Configuration.instance.getEmail();
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
        backgroundColor: colors.backgroundBase,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: colors.iconColor,
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: _getBody(isFormValid),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ButtonComponent(
          key: const ValueKey("verifyPasswordButton"),
          label: context.l10n.verifyPassword,
          isDisabled: !isFormValid,
          onTap: isFormValid ? _verifyPassword : null,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Future<void> _verifyPassword() async {
    if (_passwordController.text.isEmpty) {
      return;
    }
    FocusScope.of(context).unfocus();
    final dialog = createProgressDialog(context, context.l10n.pleaseWait);
    await dialog.show();
    try {
      final attributes = Configuration.instance.getKeyAttributes()!;
      final Uint8List keyEncryptionKey = await CryptoUtil.deriveKey(
        utf8.encode(_passwordController.text),
        CryptoUtil.base642bin(attributes.kekSalt),
        attributes.memLimit!,
        attributes.opsLimit!,
      );
      CryptoUtil.decryptSync(
        CryptoUtil.base642bin(attributes.encryptedKey),
        keyEncryptionKey,
        CryptoUtil.base642bin(attributes.keyDecryptionNonce),
      );
      await dialog.show();
      // pop
      await widget.onPasswordVerified(keyEncryptionKey);
      await dialog.hide();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, s) {
      _logger.severe("Error while verifying password", e, s);
      await dialog.hide();
      if (widget.onPasswordError != null) {
        widget.onPasswordError!();
      } else {
        if (!mounted) return;
        // ignore: unawaited_futures
        showAlertBottomSheet(
          context,
          title: context.l10n.incorrectPasswordTitle,
          message: context.l10n.pleaseTryAgain,
          assetPath: 'assets/warning-grey.png',
        );
      }
    }
  }

  Widget _getBody(bool isFormValid) {
    return Column(
      children: [
        Expanded(
          child: AutofillGroup(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 30, left: 20, right: 20),
                  child: Text(
                    context.l10n.enterPassword,
                    style: TextStyles.display2.copyWith(
                      color: context.componentColors.textBase,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 30,
                    left: 22,
                    right: 20,
                  ),
                  child: Text(
                    email ?? '',
                    style: TextStyles.mini.copyWith(
                      color: context.componentColors.textLight,
                    ),
                  ),
                ),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: TextInputComponent(
                    key: const ValueKey("passwordInputField"),
                    controller: _passwordController,
                    hintText: context.l10n.enterYourPassword,
                    autofocus: true,
                    autocorrect: false,
                    isPasswordInput: true,
                    keyboardType: TextInputType.visiblePassword,
                    autofillHints: const [AutofillHints.password],
                    shouldUnfocusOnClearOrSubmit: true,
                    onSubmit: isFormValid ? (_) => _verifyPassword() : null,
                    onChanged: (_) {
                      setState(() {});
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Divider(
                    thickness: 1,
                    color: context.componentColors.strokeFaint,
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
