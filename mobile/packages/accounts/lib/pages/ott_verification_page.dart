import 'package:dots_indicator/dots_indicator.dart';
import 'package:ente_accounts/ente_accounts.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/buttons/dynamic_fab.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pinput/pinput.dart';

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
  bool _isSubmitting = false;

  Future<void> onPressed() async {
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
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isCreateAccountScreen && !isKeypadOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: DotsIndicator(
                dotsCount: 3,
                position: 1,
                decorator: DotsDecorator(
                  activeColor: colorScheme.primary700,
                  color: colorScheme.primary700.withValues(alpha: 0.32),
                  activeShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  size: const Size(10, 10),
                  activeSize: const Size(20, 10),
                  spacing: const EdgeInsets.all(6),
                ),
              ),
            ),
          DynamicFAB(
            isKeypadOpen: isKeypadOpen,
            isFormValid: _pinController.text.length == 6 && !_isSubmitting,
            buttonText: context.strings.verify,
            onPressedFunction: onPressed,
          ),
        ],
      ),
      floatingActionButtonLocation: fabLocation(),
      floatingActionButtonAnimator: NoScalingAnimation(),
    );
  }

  Widget _getBody() {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    final defaultPinTheme = PinTheme(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        color: colorScheme.backdropBase,
        border: Border.all(color: colorScheme.strokeFaint, width: 1.75),
        borderRadius: BorderRadius.circular(18),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        color: colorScheme.backdropBase,
        border: Border.all(color: colorScheme.primary700, width: 1.75),
        borderRadius: BorderRadius.circular(18),
      ),
    );

    final submittedPinTheme = defaultPinTheme.copyWith(
      textStyle: textTheme.h3Bold.copyWith(color: colorScheme.primary700),
      decoration: BoxDecoration(
        color: colorScheme.backdropBase,
        border: Border.all(color: colorScheme.strokeFaint, width: 1.75),
        borderRadius: BorderRadius.circular(18),
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              Image.asset('assets/upload_file.png'),
              const SizedBox(height: 24),
              Text(
                context.strings.weHaveSentCode(widget.email),
                style: textTheme.body.copyWith(color: colorScheme.textBase),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                context.strings.checkInboxAndSpamFolder,
                style: textTheme.small.copyWith(color: colorScheme.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Pinput(
                length: 6,
                controller: _pinController,
                autofocus: true,
                defaultPinTheme: defaultPinTheme,
                focusedPinTheme: focusedPinTheme,
                submittedPinTheme: submittedPinTheme,
                showCursor: false,
                keyboardType: TextInputType.number,
                onCompleted: (value) {
                  if (value.length == 6) {
                    onPressed();
                  }
                },
                onChanged: (_) {
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    UserService.instance.sendOtt(
                      context,
                      widget.email,
                      isCreateAccountScreen: widget.isCreateAccountScreen,
                      isChangeEmail: widget.isChangeEmail,
                      isResetPasswordScreen: widget.isResetPasswordScreen,
                    );
                  },
                  child: Text(
                    context.strings.resendCode,
                    style: textTheme.small.copyWith(
                      color: colorScheme.primary700,
                      decoration: TextDecoration.underline,
                      decorationColor: colorScheme.primary700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
