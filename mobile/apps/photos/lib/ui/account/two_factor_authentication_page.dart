import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/account/two_factor.dart";
import 'package:photos/services/account/user_service.dart';
import 'package:photos/ui/lifecycle_event_handler.dart';
import "package:pinput/pinput.dart";

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
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleEventHandler);
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Scaffold(
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
          AppLocalizations.of(context).twoFAVerification,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        centerTitle: true,
      ),
      body: _getBody(),
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
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context).twoFAVerification,
              style: TextStyles.body.copyWith(color: colors.textBase),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(
                context,
              ).enterThe6digitCodeFromnyourAuthenticatorApp,
              style: TextStyles.body.copyWith(color: colors.textLight),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Center(
              child: Pinput(
                length: 6,
                onCompleted: (String code) {
                  _verifyTwoFactorCode(code);
                },
                onChanged: (String pin) {
                  setState(() {
                    _code = pin;
                  });
                },
                autofocus: true,
                controller: _pinController,
                defaultPinTheme: defaultPinTheme,
                focusedPinTheme: focusedPinTheme,
                submittedPinTheme: submittedPinTheme,
                followingPinTheme: defaultPinTheme,
              ),
            ),
            const Spacer(),
            ButtonComponent(
              label: AppLocalizations.of(context).verify,
              isDisabled: _code.length != 6,
              onTap: _code.length == 6
                  ? () => _verifyTwoFactorCode(_code)
                  : null,
            ),
            const SizedBox(height: 16),
            Center(
              child: ButtonComponent(
                label: AppLocalizations.of(context).lostDevice,
                variant: ButtonComponentVariant.link,
                size: ButtonComponentSize.small,
                onTap: () async {
                  // ignore: unawaited_futures
                  UserService.instance.recoverTwoFactor(
                    context,
                    widget.sessionID,
                    TwoFactorType.totp,
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _verifyTwoFactorCode(String code) async {
    await UserService.instance.verifyTwoFactor(context, widget.sessionID, code);
  }
}
