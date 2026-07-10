import 'dart:async';
import 'dart:io';

import 'package:bip39/bip39.dart' as bip39;
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/constants.dart';
import "package:photos/generated/l10n.dart";
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

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.title ?? AppLocalizations.of(context).recoveryKey,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        centerTitle: true,
        backgroundColor: colors.backgroundBase,
        leading: widget.isOnboarding
            ? const SizedBox.shrink()
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                color: colors.iconColor,
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
      ),
      body: SafeArea(child: _getBody(recoveryKey)),
    );
  }

  Widget _getBody(String recoveryKey) {
    final colors = context.componentColors;
    final lightComponentTheme = ComponentTheme.lightTheme(
      app: ComponentApp.photos,
    );
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Image.asset(
                    'assets/recovery_key.png',
                    width: 100,
                    height: 100,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.text ??
                      AppLocalizations.of(context).recoveryKeyOnForgotPassword,
                  textAlign: TextAlign.center,
                  style: TextStyles.body.copyWith(color: colors.textBase),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.subText ??
                      AppLocalizations.of(context).recoveryKeySaveDescription,
                  textAlign: TextAlign.center,
                  style: TextStyles.body.copyWith(color: colors.textLight),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              recoveryKey,
                              style: TextStyles.body.copyWith(
                                color: colors.specialWhite,
                                height: 24 / 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () async {
                              await Clipboard.setData(
                                ClipboardData(text: recoveryKey),
                              );
                              if (!mounted) return;
                              showShortToast(
                                context,
                                AppLocalizations.of(
                                  context,
                                ).recoveryKeyCopiedToClipboard,
                              );
                            },
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedCopy01,
                              color: colors.specialWhite,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Theme(
                        data: lightComponentTheme,
                        child: ButtonComponent(
                          variant: ButtonComponentVariant.secondary,
                          shouldSurfaceExecutionStates: false,
                          label: AppLocalizations.of(context).shareKey,
                          onTap: () async {
                            unawaited(_shareRecoveryKey(recoveryKey));
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.isOnboarding)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: ButtonComponent(label: widget.doneText, onTap: _saveKeys),
          ),
      ],
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
