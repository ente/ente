import 'dart:io' as io;

import 'package:bip39/bip39.dart' as bip39;
import 'package:ente_components/ente_components.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_configuration/constants.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:locker/services/configuration.dart';
import "package:share_plus/share_plus.dart";

class RecoveryKeySheet extends StatefulWidget {
  final String recoveryKey;

  const RecoveryKeySheet({super.key, required this.recoveryKey});

  @override
  State<RecoveryKeySheet> createState() => _RecoveryKeySheetState();
}

class _RecoveryKeySheetState extends State<RecoveryKeySheet> {
  late final io.File _recoveryKeyFile;
  late final BaseConfiguration _config;

  @override
  void initState() {
    super.initState();
    _config = Configuration.instance;
    _recoveryKeyFile = io.File(
      "${_config.getTempDirectory()}ente-recovery-key.txt",
    );
  }

  @override
  void dispose() {
    // Clean up temp file if it exists
    if (_recoveryKeyFile.existsSync()) {
      _recoveryKeyFile.deleteSync();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    // Convert recovery key to mnemonic words
    final String recoveryKeyMnemonic = bip39.entropyToMnemonic(
      widget.recoveryKey,
    );

    if (recoveryKeyMnemonic.split(' ').length != mnemonicKeyWordCount) {
      throw AssertionError(
        'Recovery code should have $mnemonicKeyWordCount words',
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.strings.recoveryKeyOnForgotPassword,
          style: TextStyles.body.copyWith(color: colors.textLight),
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 24,
                ),
                child: SelectableText(
                  recoveryKeyMnemonic,
                  style: TextStyles.body.copyWith(
                    color: colors.specialWhite,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                  textAlign: TextAlign.justify,
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButtonComponent(
                  variant: IconButtonComponentVariant.secondary,
                  tooltip: 'Copy to clipboard',
                  shouldSurfaceExecutionStates: false,
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedCopy01,
                    size: IconSizes.small,
                    color: colors.specialWhite,
                  ),
                  onTap: () => _copyToClipboard(recoveryKeyMnemonic),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          context.strings.recoveryKeySaveDescription,
          style: TextStyles.body.copyWith(color: colors.textLight),
        ),
        const SizedBox(height: 24),
        ButtonComponent(
          label: 'Share recovery key',
          onTap: () => _shareRecoveryKey(recoveryKeyMnemonic),
        ),
      ],
    );
  }

  Future<void> _copyToClipboard(String recoveryKey) async {
    await Clipboard.setData(ClipboardData(text: recoveryKey));
    if (mounted) {
      showShortToast(context, context.strings.recoveryKeyCopiedToClipboard);
    }
  }

  Future<void> _shareRecoveryKey(String recoveryKey) async {
    try {
      if (_recoveryKeyFile.existsSync()) {
        await _recoveryKeyFile.delete();
      }
      _recoveryKeyFile.writeAsStringSync(recoveryKey);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(_recoveryKeyFile.path)]),
      );
    } catch (e) {
      if (mounted) {
        await showErrorBottomSheetComponent<void>(
          context: context,
          message: e.toString(),
          title: context.strings.somethingWentWrong,
        );
      }
    }
  }
}

Future<void> showRecoveryKeySheet(
  BuildContext context, {
  required String recoveryKey,
}) {
  return showBottomSheetComponent<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => BottomSheetComponent(
      title: context.strings.recoveryKey,
      showCloseButton: true,
      content: RecoveryKeySheet(recoveryKey: recoveryKey),
    ),
  );
}
