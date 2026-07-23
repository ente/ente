import 'package:ente_accounts/ente_accounts.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/buttons/dynamic_fab.dart';
import 'package:ente_ui/lifecycle_event_handler.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pinput/pinput.dart';

class TwoFactorAuthenticationPage extends StatefulWidget {
  final String sessionID;

  const TwoFactorAuthenticationPage(this.sessionID, {super.key});

  @override
  State<TwoFactorAuthenticationPage> createState() =>
      _TwoFactorAuthenticationPageState();
}

class _TwoFactorAuthenticationPageState
    extends State<TwoFactorAuthenticationPage> {
  final _pinController = TextEditingController();
  String _code = "";
  late LifecycleEventHandler _lifecycleEventHandler;

  @override
  void initState() {
    super.initState();
    _lifecycleEventHandler = LifecycleEventHandler(
      resumeCallBack: () async {
        if (mounted) {
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          if (data != null && data.text != null && data.text!.length == 6) {
            _pinController.text = data.text!;
          }
        }
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleEventHandler);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleEventHandler);
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
      floatingActionButton: DynamicFAB(
        isKeypadOpen: isKeypadOpen,
        isFormValid: _code.length == 6,
        buttonText: context.strings.verify,
        onPressedFunction: () async {
          await _verifyTwoFactorCode(_code);
        },
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
              Image.asset(
                'assets/lock_screen_icon.png',
                width: 129,
                height: 95,
              ),
              const SizedBox(height: 24),
              Text(
                context.strings.twoFactorAuthTitle,
                style: textTheme.body.copyWith(color: colorScheme.textBase),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                context.strings.enterCodeHint,
                style: textTheme.small.copyWith(color: colorScheme.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Pinput(
                length: 6,
                controller: _pinController,
                autofocus: true,
                keyboardType: TextInputType.number,
                defaultPinTheme: defaultPinTheme,
                focusedPinTheme: focusedPinTheme,
                submittedPinTheme: submittedPinTheme,
                showCursor: false,
                onCompleted: (String code) {
                  _verifyTwoFactorCode(code);
                },
                onChanged: (String pin) {
                  setState(() {
                    _code = pin;
                  });
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    UserService.instance.recoverTwoFactor(
                      context,
                      widget.sessionID,
                      TwoFactorType.totp,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      context.strings.lostDeviceTitle,
                      style: textTheme.small.copyWith(
                        color: colorScheme.primary700,
                        decoration: TextDecoration.underline,
                        decorationColor: colorScheme.primary700,
                      ),
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

  Future<void> _verifyTwoFactorCode(String code) async {
    await UserService.instance.verifyTwoFactor(context, widget.sessionID, code);
  }
}
