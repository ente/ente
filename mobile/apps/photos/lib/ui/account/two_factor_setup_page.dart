import 'dart:async';

import 'package:ente_crypto/ente_crypto.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:flutter/material.dart";
import 'package:flutter/services.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/ente_theme_data.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/services/account/user_service.dart';
import 'package:photos/ui/account/recovery_key_page.dart';
import 'package:photos/ui/lifecycle_event_handler.dart';
import 'package:photos/ui/notification/toast.dart';
import "package:pinput/pinput.dart";

class TwoFactorSetupPage extends StatefulWidget {
  final String secretCode;
  final String qrCode;
  final Completer completer;

  const TwoFactorSetupPage(
    this.secretCode,
    this.qrCode,
    this.completer, {
    super.key,
  });

  @override
  State<TwoFactorSetupPage> createState() => _TwoFactorSetupPageState();
}

class _TwoFactorSetupPageState extends State<TwoFactorSetupPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _pinController = TextEditingController();
  final _pinPutDecoration = PinTheme(
    height: 45,
    width: 45,
    decoration: BoxDecoration(
      border: Border.all(color: const Color.fromRGBO(45, 194, 98, 1.0)),
      borderRadius: BorderRadius.circular(15.0),
    ),
  );
  String _code = "";
  late ImageProvider _imageProvider;
  late LifecycleEventHandler _lifecycleEventHandler;

  @override
  void initState() {
    _tabController = TabController(length: 2, vsync: this);
    _imageProvider = Image.memory(
      CryptoUtil.base642bin(widget.qrCode),
      height: 180,
      width: 180,
    ).image;
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
    widget.completer.isCompleted ? null : widget.completer.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(AppLocalizations.of(context).twofactorSetup),
      ),
      body: _getBody(),
    );
  }

  Widget _getBody() {
    return SingleChildScrollView(
      reverse: true,
      child: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: 360,
              child: Column(
                children: [
                  TabBar(
                    labelColor: Theme.of(context).colorScheme.greenAlternative,
                    unselectedLabelColor: Colors.grey,
                    tabs: [
                      Tab(text: AppLocalizations.of(context).enterCode),
                      Tab(text: AppLocalizations.of(context).scanCode),
                    ],
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [_getSecretCode(), _getBarCode()],
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: Theme.of(context).colorScheme.secondary,
            ),
            _getVerificationWidget(),
          ],
        ),
      ),
    );
  }

  Widget _getSecretCode() {
    final Color textColor = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: widget.secretCode));
        if (!mounted) return;
        showShortToast(
          context,
          AppLocalizations.of(context).codeCopiedToClipboard,
        );
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Padding(padding: EdgeInsets.all(12)),
          Text(
            AppLocalizations.of(
              context,
            ).copypasteThisCodentoYourAuthenticatorApp,
            style: const TextStyle(height: 1.4, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const Padding(padding: EdgeInsets.all(16)),
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              color: textColor.withValues(alpha: 0.1),
              child: Center(
                child: Text(
                  widget.secretCode,
                  style: TextStyle(
                    fontSize: 15,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.all(6)),
          Text(
            AppLocalizations.of(context).tapToCopy,
            style: TextStyle(color: textColor.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _getBarCode() {
    return Center(
      child: Column(
        children: [
          const Padding(padding: EdgeInsets.all(12)),
          Text(
            AppLocalizations.of(
              context,
            ).scanThisBarcodeWithnyourAuthenticatorApp,
            style: const TextStyle(height: 1.4, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const Padding(padding: EdgeInsets.all(12)),
          Image(image: _imageProvider, height: 180, width: 180),
        ],
      ),
    );
  }

  Widget _getVerificationWidget() {
    return Column(
      children: [
        const Padding(padding: EdgeInsets.all(12)),
        Text(
          AppLocalizations.of(
            context,
          ).enterThe6digitCodeFromnyourAuthenticatorApp,
          style: const TextStyle(height: 1.4, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const Padding(padding: EdgeInsets.all(16)),
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 0),
          child: Pinput(
            length: 6,
            onCompleted: (String code) {
              _enableTwoFactor(code);
            },
            onChanged: (String pin) {
              setState(() {
                _code = pin;
              });
            },
            controller: _pinController,
            submittedPinTheme: _pinPutDecoration.copyWith(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(
                  color: const Color.fromRGBO(45, 194, 98, 0.5),
                ),
              ),
            ),
            defaultPinTheme: _pinPutDecoration,
            followingPinTheme: _pinPutDecoration.copyWith(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(
                  color: const Color.fromRGBO(45, 194, 98, 0.5),
                ),
              ),
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.all(24)),
        OutlinedButton(
          onPressed: _code.length == 6
              ? () async {
                  await _enableTwoFactor(_code);
                }
              : null,
          child: Text(AppLocalizations.of(context).confirm),
        ),
        const Padding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }

  Future<void> _enableTwoFactor(String code) async {
    final success = await UserService.instance.enableTwoFactor(
      context,
      widget.secretCode,
      code,
    );
    if (success) {
      _showSuccessPage();
    }
  }

  void _showSuccessPage() {
    final recoveryKey = CryptoUtil.bin2hex(
      Configuration.instance.getRecoveryKey(),
    );
    routeToPage(
      context,
      RecoveryKeyPage(
        recoveryKey,
        AppLocalizations.of(context).ok,
        isOnboarding: false,
        onDone: () {},
        title: AppLocalizations.of(context).setupComplete,
        text: AppLocalizations.of(
          context,
        ).saveYourRecoveryKeyIfYouHaventAlready,
        subText: AppLocalizations.of(
          context,
        ).thisCanBeUsedToRecoverYourAccountIfYou,
      ),
    );
  }
}
