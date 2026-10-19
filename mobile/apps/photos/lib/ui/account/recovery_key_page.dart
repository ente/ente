import 'dart:async';
import 'dart:io';

import 'package:bip39/bip39.dart' as bip39;
import 'package:ente_components/ente_components.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/constants.dart';
import "package:photos/ui/account/onboarding_page_scaffold.dart";
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/utils/share_util.dart';
import 'package:share_plus/share_plus.dart';

class RecoveryKeyPage extends StatefulWidget {
  final String recoveryKey;
  final String doneText;
  final Function()? onDone;
  final String? title;
  final String? text;
  final String? subText;
  final bool isOnboarding;

  const RecoveryKeyPage(
    this.recoveryKey,
    this.doneText, {
    super.key,
    this.onDone,
    this.title,
    this.text,
    this.subText,
    this.isOnboarding = false,
  });

  @override
  State<RecoveryKeyPage> createState() => _RecoveryKeyPageState();
}

class _RecoveryKeyPageState extends State<RecoveryKeyPage> {
  final _recoveryKeyFile = File(
    Configuration.instance.getTempDirectory() + "ente-recovery-key.txt",
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    final String recoveryKey = bip39.entropyToMnemonic(widget.recoveryKey);
    if (recoveryKey.split(' ').length != mnemonicKeyWordCount) {
      throw AssertionError(
        'recovery code should have $mnemonicKeyWordCount words',
      );
    }

    if (widget.isOnboarding) {
      return OnboardingPageScaffold(
        title: widget.title ?? context.strings.recoveryKey,
        illustration: OnboardingIllustration.recoveryKey,
        showBackButton: false,
        isBodyCentered: true,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDescription(recoveryKey, spacing: Spacing.sm),
            const SizedBox(height: Spacing.lg),
            _buildKeyCard(recoveryKey),
          ],
        ),
        actions: [ButtonComponent(label: widget.doneText, onTap: _saveKeys)],
      );
    }

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.title ?? context.strings.recoveryKey,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        centerTitle: true,
        backgroundColor: colors.backgroundBase,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: colors.iconColor,
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Image.asset('assets/recovery_key.png', width: 100, height: 100),
              const SizedBox(height: 24),
              _buildDescription(recoveryKey, spacing: Spacing.xl),
              const SizedBox(height: Spacing.xl),
              _buildKeyCard(recoveryKey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDescription(String recoveryKey, {required double spacing}) {
    final colors = context.componentColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.text ?? context.strings.recoveryKeyOnForgotPassword,
          textAlign: TextAlign.center,
          style: TextStyles.body.copyWith(color: colors.textBase),
        ),
        SizedBox(height: spacing),
        Text(
          widget.subText ?? context.strings.recoveryKeySaveShortDescription,
          textAlign: TextAlign.center,
          style: TextStyles.body.copyWith(color: colors.textLight),
        ),
      ],
    );
  }

  Widget _buildKeyCard(String recoveryKey) {
    final colors = context.componentColors;
    final lightComponentTheme = ComponentTheme.lightTheme(
      app: ComponentApp.photos,
    );
    return Container(
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(Radii.button),
      ),
      padding: const EdgeInsets.all(Spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  recoveryKey,
                  style: TextStyles.body.copyWith(color: colors.specialWhite),
                ),
              ),
              const SizedBox(width: Spacing.xs),
              IconButtonComponent(
                variant: IconButtonComponentVariant.unfilled,
                iconSize: IconSizes.small,
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedCopy01,
                  color: colors.specialWhite,
                ),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: recoveryKey));
                  if (!mounted) return;
                  showShortToast(
                    context,
                    context.strings.recoveryKeyCopiedToClipboard,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Theme(
            data: lightComponentTheme,
            child: ButtonComponent(
              variant: ButtonComponentVariant.secondary,
              shouldSurfaceExecutionStates: false,
              label: context.strings.shareKey,
              onTap: () async {
                unawaited(_shareRecoveryKey(recoveryKey));
              },
            ),
          ),
        ],
      ),
    );
  }

  Future _shareRecoveryKey(String recoveryKey) async {
    if (_recoveryKeyFile.existsSync()) {
      await _recoveryKeyFile.delete();
    }
    _recoveryKeyFile.writeAsStringSync(recoveryKey);

    if (!mounted) return null;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(_recoveryKeyFile.path)],
        sharePositionOrigin: shareButtonRect(context, null),
      ),
    );
  }

  Future<void> _saveKeys() async {
    Navigator.of(context).pop();
    if (_recoveryKeyFile.existsSync()) {
      await _recoveryKeyFile.delete();
    }
    widget.onDone!();
  }
}
