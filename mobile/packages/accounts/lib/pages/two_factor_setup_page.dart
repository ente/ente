import 'dart:async';

import 'package:ente_accounts/lifecycle_event_handler.dart';
import 'package:ente_accounts/pages/recovery_key_page.dart';
import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:pinput/pinput.dart';

class TwoFactorSetupPage extends StatefulWidget {
  const TwoFactorSetupPage(
    this.config,
    this.secretCode,
    this.qrCode, {
    super.key,
  });

  final BaseConfiguration config;
  final String secretCode;
  final String qrCode;

  @override
  State<TwoFactorSetupPage> createState() => _TwoFactorSetupPageState();
}

class _TwoFactorSetupPageState extends State<TwoFactorSetupPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _pinController = TextEditingController();
  late final ImageProvider _qrImage;
  late final LifecycleEventHandler _lifecycleEventHandler;
  var _code = '';
  var _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _qrImage = MemoryImage(CryptoUtil.base642bin(widget.qrCode));
    _lifecycleEventHandler = LifecycleEventHandler(
      resumeCallBack: () async {
        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
        final clipboardCode = clipboardData?.text?.trim();
        if (mounted &&
            clipboardCode != null &&
            RegExp(r'^\d{6}$').hasMatch(clipboardCode)) {
          _pinController.text = clipboardCode;
        }
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleEventHandler);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleEventHandler);
    _tabController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return SettingsPageScaffold(
      title: context.strings.twofactorSetup,
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        0,
        Spacing.lg,
        Spacing.lg + keyboardInset,
      ),
      children: [
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            final selectedTab = _tabController.index;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    TagChipComponent(
                      label: context.strings.enterCode,
                      state: selectedTab == 0
                          ? TagChipComponentState.selected
                          : TagChipComponentState.unselected,
                      onTap: () => _tabController.animateTo(0),
                    ),
                    const SizedBox(width: Spacing.sm),
                    TagChipComponent(
                      label: context.strings.scanCode,
                      state: selectedTab == 1
                          ? TagChipComponentState.selected
                          : TagChipComponentState.unselected,
                      onTap: () => _tabController.animateTo(1),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      AnimatedSize(
                        duration: Motion.standard,
                        curve: Curves.easeInOutCubic,
                        child: selectedTab == 0
                            ? _buildSecretCode()
                            : _buildQrCode(),
                      ),
                      const SizedBox(height: 36),
                      _buildVerification(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSecretCode() {
    final colors = context.componentColors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Text(
            context.strings.copypasteThisCodentoYourAuthenticatorApp,
            style: TextStyles.body.copyWith(color: colors.textLight),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: Spacing.md),
        TextInputComponent(
          initialValue: widget.secretCode,
          readOnly: true,
          maxLines: 2,
          minLines: 2,
          suffix: HugeIcon(
            icon: HugeIcons.strokeRoundedCopy01,
            color: colors.textBase,
            size: IconSizes.small,
          ),
          onSuffixTap: () async {
            await Clipboard.setData(ClipboardData(text: widget.secretCode));
            if (mounted) {
              showShortToast(context, context.strings.codeCopiedToClipboard);
            }
          },
        ),
      ],
    );
  }

  Widget _buildQrCode() {
    final colors = context.componentColors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
          child: Text(
            context.strings.scanThisBarcodeWithnyourAuthenticatorApp,
            style: TextStyles.body.copyWith(color: colors.textLight),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: Spacing.md),
        Semantics(
          image: true,
          label: context.strings.scanThisBarcodeWithnyourAuthenticatorApp,
          child: Container(
            width: 159,
            height: 158,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.specialWhite,
              border: Border.all(color: colors.strokeDark),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Image(image: _qrImage, height: 135, width: 135),
          ),
        ),
      ],
    );
  }

  Widget _buildVerification() {
    final colors = context.componentColors;
    final defaultPinTheme = PinTheme(
      height: 52,
      width: 49,
      textStyle: TextStyles.h1.copyWith(color: colors.textBase),
      decoration: BoxDecoration(
        color: colors.fillLight,
        border: Border.all(color: colors.strokeDark),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
    );
    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        color: colors.fillLight,
        border: Border.all(color: colors.primary),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: Text(
            context.strings.enterThe6digitCodeFromnyourAuthenticatorApp,
            style: TextStyles.body.copyWith(color: colors.textLight),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: Spacing.xxl),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Pinput(
              length: 6,
              controller: _pinController,
              enabled: !_isSubmitting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              defaultPinTheme: defaultPinTheme,
              focusedPinTheme: focusedPinTheme,
              submittedPinTheme: defaultPinTheme,
              separatorBuilder: (_) => const SizedBox(width: 6),
              showCursor: false,
              onCompleted: (code) => unawaited(_enableTwoFactor(code)),
              onChanged: (code) => setState(() => _code = code),
            ),
          ),
        ),
        const SizedBox(height: Spacing.xxl),
        ButtonComponent(
          label: context.strings.confirm,
          isDisabled: _code.length != 6 || _isSubmitting,
          shouldShowSuccessState: false,
          onTap: () => _enableTwoFactor(_code),
        ),
      ],
    );
  }

  Future<void> _enableTwoFactor(String code) async {
    if (_isSubmitting) {
      return;
    }
    setState(() => _isSubmitting = true);
    final success = await UserService.instance.enableTwoFactor(
      context,
      widget.secretCode,
      code,
    );
    if (!mounted) {
      return;
    }
    if (!success) {
      setState(() => _isSubmitting = false);
      return;
    }

    final strings = context.strings;
    final recoveryKey = CryptoUtil.bin2hex(widget.config.getRecoveryKey());
    unawaited(
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => RecoveryKeyPage(
            widget.config,
            recoveryKey,
            strings.ok,
            title: strings.setupComplete,
            text: strings.saveYourRecoveryKeyIfYouHaventAlready,
            subText: strings.thisCanBeUsedToRecoverYourAccountIfYou,
            onDone: () {},
          ),
        ),
      ),
    );
  }
}
