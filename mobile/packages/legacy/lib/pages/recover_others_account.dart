import "dart:convert";

import "package:ente_accounts/models/set_keys_request.dart";
import "package:ente_base/models/key_attributes.dart";
import "package:ente_crypto_api/ente_crypto_api.dart";
import "package:ente_legacy/models/emergency_models.dart";
import "package:ente_legacy/services/emergency_service.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/buttons/dynamic_fab.dart";
import "package:ente_ui/utils/dialog_util.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:password_strength/password_strength.dart";

class RecoverOthersAccount extends StatefulWidget {
  final String recoveryKey;
  final KeyAttributes attributes;
  final RecoverySessions sessions;

  const RecoverOthersAccount(
    this.recoveryKey,
    this.attributes,
    this.sessions, {
    super.key,
  });

  @override
  State<RecoverOthersAccount> createState() => _RecoverOthersAccountState();
}

class _RecoverOthersAccountState extends State<RecoverOthersAccount> {
  static const kMildPasswordStrengthThreshold = 0.4;
  static const kStrongPasswordStrengthThreshold = 0.7;

  final _logger = Logger((_RecoverOthersAccountState).toString());
  final _passwordController1 = TextEditingController(),
      _passwordController2 = TextEditingController();
  final Color _validFieldValueColor = const Color.fromRGBO(45, 194, 98, 0.2);
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

  @override
  void initState() {
    super.initState();
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

    String title = context.strings.setPasswordTitle;
    title = context.strings.resetPasswordTitle;
    return Scaffold(
      resizeToAvoidBottomInset: isKeypadOpen,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: Theme.of(context).iconTheme.color,
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        elevation: 0,
      ),
      body: _getBody(title),
      floatingActionButton: DynamicFAB(
        isKeypadOpen: isKeypadOpen,
        isFormValid: _passwordsMatch && _isPasswordValid,
        buttonText: title,
        onPressedFunction: () {
          _updatePassword();
          FocusScope.of(context).unfocus();
        },
      ),
      floatingActionButtonLocation: fabLocation(),
      floatingActionButtonAnimator: NoScalingAnimation(),
    );
  }

  Widget _getBody(String buttonTextAndHeading) {
    final email = widget.sessions.user.email;
    var passwordStrengthText = context.strings.weakStrength;
    var passwordStrengthColor = Colors.redAccent;
    if (_passwordStrength > kStrongPasswordStrengthThreshold) {
      passwordStrengthText = context.strings.strongStrength;
      passwordStrengthColor = Colors.greenAccent;
    } else if (_passwordStrength > kMildPasswordStrengthThreshold) {
      passwordStrengthText = context.strings.moderateStrength;
      passwordStrengthColor = Colors.orangeAccent;
    }
    return Column(
      children: [
        Expanded(
          child: AutofillGroup(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 30,
                    horizontal: 20,
                  ),
                  child: Text(
                    buttonTextAndHeading,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    "Enter new password for $email account. You will be able "
                    "to use this password to login into $email account.",
                    textAlign: TextAlign.start,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium!.copyWith(fontSize: 14.0),
                  ),
                ),
                const Padding(padding: EdgeInsets.all(12)),
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
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: TextFormField(
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      fillColor: _isPasswordValid
                          ? _validFieldValueColor
                          : null,
                      filled: true,
                      hintText: context.strings.password,
                      contentPadding: const EdgeInsets.all(20),
                      border: UnderlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      suffixIcon: _password1InFocus
                          ? IconButton(
                              icon: Icon(
                                _password1Visible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Theme.of(context).iconTheme.color,
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() {
                                  _password1Visible = !_password1Visible;
                                });
                              },
                            )
                          : null,
                    ),
                    obscureText: !_password1Visible,
                    controller: _passwordController1,
                    autofocus: false,
                    autocorrect: false,
                    keyboardType: TextInputType.visiblePassword,
                    onChanged: (password) {
                      setState(() {
                        _passwordInInputBox = password;
                        _passwordStrength = estimatePasswordStrength(password);
                        _isPasswordValid =
                            _passwordStrength >= kMildPasswordStrengthThreshold;
                        _passwordsMatch =
                            _passwordInInputBox ==
                            _passwordInInputConfirmationBox;
                      });
                    },
                    textInputAction: TextInputAction.next,
                    focusNode: _password1FocusNode,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: TextFormField(
                    keyboardType: TextInputType.visiblePassword,
                    controller: _passwordController2,
                    obscureText: !_password2Visible,
                    autofillHints: const [AutofillHints.newPassword],
                    onEditingComplete: () => TextInput.finishAutofillContext(),
                    decoration: InputDecoration(
                      fillColor: _passwordsMatch ? _validFieldValueColor : null,
                      filled: true,
                      hintText: context.strings.confirmPassword,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 20,
                        horizontal: 20,
                      ),
                      suffixIcon: _password2InFocus
                          ? IconButton(
                              icon: Icon(
                                _password2Visible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Theme.of(context).iconTheme.color,
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() {
                                  _password2Visible = !_password2Visible;
                                });
                              },
                            )
                          : null,
                      border: UnderlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    focusNode: _password2FocusNode,
                    onChanged: (cnfPassword) {
                      setState(() {
                        _passwordInInputConfirmationBox = cnfPassword;
                        if (_passwordInInputBox != '') {
                          _passwordsMatch =
                              _passwordInInputBox ==
                              _passwordInInputConfirmationBox;
                        }
                      });
                    },
                  ),
                ),
                Opacity(
                  opacity: (_passwordInInputBox != '') && _password1InFocus
                      ? 1
                      : 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Text(
                      "Password strength: $passwordStrengthText",
                      style: TextStyle(color: passwordStrengthColor),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(padding: EdgeInsets.all(20)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _updatePassword() async {
    final dialog = createProgressDialog(
      context,
      context.strings.generatingEncryptionKeys,
    );
    await dialog.show();
    try {
      final String password = _passwordController1.text;
      final KeyAttributes attributes = widget.attributes;
      Uint8List? masterKey;
      try {
        // Decrypt the master key that was earlier encrypted with the recovery key
        masterKey = await CryptoUtil.decrypt(
          CryptoUtil.base642bin(attributes.masterKeyEncryptedWithRecoveryKey),
          CryptoUtil.hex2bin(widget.recoveryKey),
          CryptoUtil.base642bin(attributes.masterKeyDecryptionNonce),
        );
      } catch (e) {
        _logger.severe(e, "Failed to get master key using recoveryKey");
        rethrow;
      }

      // Derive a key from the password that will be used to encrypt and
      // decrypt the master key
      final kekSalt = CryptoUtil.getSaltToDeriveKey();
      final derivedKeyResult = await CryptoUtil.deriveSensitiveKey(
        utf8.encode(password),
        kekSalt,
      );
      final loginKey = await CryptoUtil.deriveLoginKey(derivedKeyResult.key);
      // Encrypt the key with this derived key
      final encryptedKeyData = CryptoUtil.encryptSync(
        masterKey,
        derivedKeyResult.key,
      );

      final updatedAttributes = attributes.copyWith(
        kekSalt: CryptoUtil.bin2base64(kekSalt),
        encryptedKey: CryptoUtil.bin2base64(encryptedKeyData.encryptedData!),
        keyDecryptionNonce: CryptoUtil.bin2base64(encryptedKeyData.nonce!),
        memLimit: derivedKeyResult.memLimit,
        opsLimit: derivedKeyResult.opsLimit,
      );
      final setKeyRequest = SetKeysRequest(
        kekSalt: updatedAttributes.kekSalt,
        encryptedKey: updatedAttributes.encryptedKey,
        keyDecryptionNonce: updatedAttributes.keyDecryptionNonce,
        memLimit: updatedAttributes.memLimit,
        opsLimit: updatedAttributes.opsLimit,
      );
      await EmergencyContactService.instance.changePasswordForOther(
        Uint8List.fromList(loginKey),
        setKeyRequest,
        widget.sessions,
      );
      await dialog.hide();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.strings.passwordChangedSuccessfully),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e, s) {
      _logger.severe("Failed to recover account", e, s);
      await dialog.hide();
      if (mounted) {
        await showGenericErrorDialog(context: context, error: e);
      }
    }
  }

  @override
  void dispose() {
    _passwordController1.dispose();
    _passwordController2.dispose();
    _password1FocusNode.dispose();
    _password2FocusNode.dispose();
    super.dispose();
  }
}
