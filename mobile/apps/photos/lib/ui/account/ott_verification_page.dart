import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:photos/services/account/user_service.dart';

class OTTVerificationPage extends StatefulWidget {
  final String email;
  final bool isChangeEmail;
  final bool isCreateAccountScreen;
  final bool isResetPasswordScreen;

  const OTTVerificationPage(
    this.email, {
    this.isChangeEmail = false,
    this.isCreateAccountScreen = false,
    this.isResetPasswordScreen = false,
    super.key,
  });

  @override
  State<OTTVerificationPage> createState() => _OTTVerificationPageState();
}

class _OTTVerificationPageState extends State<OTTVerificationPage> {
  final _pinController = TextEditingController();
  String _code = "";
  bool _isSubmitting = false;

  Future<void> _onVerifyPressed() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
    });
    try {
      if (widget.isChangeEmail) {
        await UserService.instance.changeEmail(
          context,
          widget.email,
          _pinController.text,
        );
      } else {
        await UserService.instance.verifyEmail(
          context,
          _pinController.text,
          isResettingPasswordScreen: widget.isResetPasswordScreen,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
    if (!mounted) {
      return;
    }
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final isFormValid = _code.length == 6 && !_isSubmitting;

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
          context.strings.verifyEmail,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        centerTitle: true,
      ),
      body: _getBody(),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ButtonComponent(
          key: const ValueKey("verifyOttButton"),
          label: context.strings.verify,
          isDisabled: !isFormValid,
          onTap: isFormValid ? _onVerifyPressed : null,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _getBody() {
    final colors = context.componentColors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Center(child: Image.asset('assets/ott.png', height: 96)),
            const SizedBox(height: 24),
            Text(
              context.strings.weHaveSentCodeTo(email: widget.email),
              style: TextStyles.body.copyWith(color: colors.textBase),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.isResetPasswordScreen
                  ? context.strings.toResetVerifyEmail
                  : context.strings.checkInboxAndSpamFolder,
              style: TextStyles.body.copyWith(color: colors.textLight),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Center(
              child: PinInputComponent(
                length: 6,
                controller: _pinController,
                autofocus: true,
                autofillHints: const [AutofillHints.oneTimeCode],
                onChanged: (String pin) {
                  setState(() {
                    _code = pin;
                  });
                },
                onCompleted: (value) {
                  if (value.length == 6) {
                    _onVerifyPressed();
                  }
                },
              ),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: ButtonComponent(
                label: context.strings.resendCode,
                variant: ButtonComponentVariant.link,
                size: ButtonComponentSize.small,
                onTap: () async {
                  // ignore: unawaited_futures
                  UserService.instance.sendOtt(
                    context,
                    widget.email,
                    isCreateAccountScreen: widget.isCreateAccountScreen,
                    isResetPasswordScreen: widget.isResetPasswordScreen,
                    isChangeEmail: widget.isChangeEmail,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
