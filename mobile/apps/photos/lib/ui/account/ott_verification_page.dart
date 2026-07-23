import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/services/account/user_service.dart';
import "package:pinput/pinput.dart";

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
          AppLocalizations.of(context).verifyEmail,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        centerTitle: true,
      ),
      body: _getBody(),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ButtonComponent(
          key: const ValueKey("verifyOttButton"),
          label: AppLocalizations.of(context).verify,
          isDisabled: !isFormValid,
          onTap: isFormValid ? _onVerifyPressed : null,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _getBody() {
    final colors = context.componentColors;
    final defaultPinTheme = PinTheme(
      height: 52,
      width: 48,
      textStyle: TextStyles.body.copyWith(color: colors.textBase),
      decoration: BoxDecoration(
        border: Border.all(color: colors.strokeFaint),
        borderRadius: BorderRadius.circular(20),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        border: Border.all(color: colors.primary, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
    );

    final submittedPinTheme = defaultPinTheme.copyWith(
      textStyle: TextStyles.h1.copyWith(color: colors.primary),
      decoration: BoxDecoration(
        color: colors.primaryLight,
        border: Border.all(color: colors.primary, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Center(child: Image.asset('assets/ott.png', height: 96)),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(
                context,
              ).weHaveSentCodeTo(email: widget.email),
              style: TextStyles.body.copyWith(color: colors.textBase),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.isResetPasswordScreen
                  ? AppLocalizations.of(context).toResetVerifyEmail
                  : AppLocalizations.of(context).checkInboxAndSpamFolder,
              style: TextStyles.body.copyWith(color: colors.textLight),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Center(
              child: Pinput(
                length: 6,
                controller: _pinController,
                autofocus: true,
                defaultPinTheme: defaultPinTheme,
                focusedPinTheme: focusedPinTheme,
                submittedPinTheme: submittedPinTheme,
                followingPinTheme: defaultPinTheme,
                keyboardType: TextInputType.number,
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
                label: AppLocalizations.of(context).resendCode,
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
