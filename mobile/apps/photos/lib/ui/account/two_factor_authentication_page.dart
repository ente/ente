import 'package:ente_components/ente_components.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import "package:photos/models/account/two_factor.dart";
import 'package:photos/services/account/user_service.dart';
import "package:photos/ui/account/onboarding_page_scaffold.dart";
import 'package:photos/ui/lifecycle_event_handler.dart';

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
  final _pinFocusNode = FocusNode();
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
    _pinFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return OnboardingPageScaffold(
      title: context.strings.twoFAVerification,
      illustration: OnboardingIllustration.key,
      minimumKeyboardHeaderHeight: OnboardingPageScaffold.compactHeaderHeight,
      isBodyCentered: true,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.strings.enterThe6digitCodeFromnyourAuthenticatorApp,
            style: TextStyles.body.copyWith(color: colors.textLight),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.xxl),
          PinInputComponent(
            length: 6,
            controller: _pinController,
            focusNode: _pinFocusNode,
            autofocus: true,
            autofillHints: const [AutofillHints.oneTimeCode],
            onChanged: (String pin) {
              setState(() {
                _code = pin;
              });
            },
            onCompleted: _verifyTwoFactorCode,
          ),
        ],
      ),
      actions: [
        ButtonComponent(
          label: context.strings.verify,
          shouldShowSuccessState: false,
          isDisabled: _code.length != 6,
          onTap: _code.length == 6 ? () => _verifyTwoFactorCode(_code) : null,
        ),
        ButtonComponent(
          label: context.strings.lostDevice,
          variant: ButtonComponentVariant.link,
          onTap: () async {
            // ignore: unawaited_futures
            UserService.instance.recoverTwoFactor(
              context,
              widget.sessionID,
              TwoFactorType.totp,
            );
          },
        ),
      ],
    );
  }

  Future<void> _verifyTwoFactorCode(String code) async {
    await UserService.instance.verifyTwoFactor(context, widget.sessionID, code);
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      _pinController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pinFocusNode.requestFocus();
      });
    }
  }
}
