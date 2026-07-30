import 'dart:convert';
import 'dart:io' as io;

import 'package:bip39/bip39.dart' as bip39;
import 'package:dots_indicator/dots_indicator.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_configuration/constants.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/buttons/gradient_button.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:ente_utils/ente_utils.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:share_plus/share_plus.dart';

class RecoveryKeyPage extends StatefulWidget {
  final BaseConfiguration config;
  final bool? showAppBar;
  final String recoveryKey;
  final String doneText;
  final Function()? onDone;
  final bool? isDismissible;
  final String? title;
  final String? text;
  final String? subText;
  final bool showProgressBar;

  const RecoveryKeyPage(
    this.config,
    this.recoveryKey,
    this.doneText, {
    super.key,
    this.showAppBar,
    this.onDone,
    this.isDismissible,
    this.title,
    this.text,
    this.subText,
    this.showProgressBar = false,
  });

  @override
  State<RecoveryKeyPage> createState() => _RecoveryKeyPageState();
}

class _RecoveryKeyPageState extends State<RecoveryKeyPage> {
  bool _hasTriedToSave = false;
  late final io.File _recoveryKeyFile;

  @override
  void initState() {
    super.initState();
    _recoveryKeyFile = io.File(
      "${widget.config.getTempDirectory()}ente-recovery-key.txt",
    );
  }

  @override
  Widget build(BuildContext context) {
    final String recoveryKey = bip39.entropyToMnemonic(widget.recoveryKey);
    if (recoveryKey.split(' ').length != mnemonicKeyWordCount) {
      throw AssertionError(
        'recovery code should have $mnemonicKeyWordCount words',
      );
    }
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: recoveryKey));
      if (context.mounted) {
        showShortToast(context, context.strings.recoveryKeyCopiedToClipboard);
        setState(() {
          _hasTriedToSave = true;
        });
      }
    }

    return Scaffold(
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
        leading: widget.showAppBar == false
            ? const SizedBox.shrink()
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  Navigator.of(context).pop();
                },
                color: colorScheme.primary700,
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Text(
                        widget.text ??
                            context.strings.recoveryKeyOnForgotPassword,
                        style: textTheme.small.copyWith(
                          color: colorScheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.primary700,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Builder(
                          builder: (context) {
                            final text = Text(
                              recoveryKey,
                              textAlign: TextAlign.justify,
                              style: textTheme.body.copyWith(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                letterSpacing: 0.5,
                                height: 1.5,
                              ),
                            );

                            final keyContent = PlatformDetector.isMobile()
                                ? GestureDetector(
                                    onTap: () async => await copy(),
                                    child: text,
                                  )
                                : SelectableRegion(
                                    focusNode: FocusNode(),
                                    selectionControls:
                                        PlatformUtil.selectionControls,
                                    child: text,
                                  );

                            return Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    24,
                                    64,
                                    24,
                                  ),
                                  child: keyContent,
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: IconButton(
                                    onPressed: () async => await copy(),
                                    icon: const HugeIcon(
                                      icon: HugeIcons.strokeRoundedCopy01,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.subText ??
                            context.strings.recoveryKeySaveDescription,
                        style: textTheme.small.copyWith(
                          color: colorScheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _saveOptions(context, recoveryKey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _saveOptions(BuildContext context, String recoveryKey) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final List<Widget> childrens = [];

    if (widget.showProgressBar) {
      childrens.add(
        Center(
          child: DotsIndicator(
            dotsCount: 3,
            position: 2,
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
      );

      childrens.add(const SizedBox(height: 20));
    }

    childrens.add(
      GradientButton(
        onTap: () async {
          await showShareSheet(
            context,
            context.strings.recoveryKey,
            saveAction: () async {
              await _saveRecoveryKey(recoveryKey);
            },
            sendAction: () async {
              await _shareRecoveryKey(recoveryKey);
            },
          );
        },
        text: context.strings.saveKey,
      ),
    );

    childrens.add(
      TextButton(
        onPressed: () async {
          await _saveKeys();
        },
        child: Text(
          _hasTriedToSave ? widget.doneText : context.strings.continueLabel,
          style: textTheme.bodyBold.copyWith(color: colorScheme.primary700),
        ),
      ),
    );

    return childrens;
  }

  Future _saveRecoveryKey(String recoveryKey) async {
    final bytes = utf8.encode(recoveryKey);
    final time = DateTime.now().millisecondsSinceEpoch;

    await FileSaverUtil.saveFile(
      "ente_recovery_key_$time",
      "txt",
      bytes,
      MimeType.text,
    );

    if (mounted) {
      showToast(context, context.strings.recoveryKeySaved);
      setState(() {
        _hasTriedToSave = true;
      });
    }
  }

  Future _shareRecoveryKey(String recoveryKey) async {
    if (_recoveryKeyFile.existsSync()) {
      await _recoveryKeyFile.delete();
    }
    _recoveryKeyFile.writeAsStringSync(recoveryKey);
    await shareFiles([
      XFile(_recoveryKeyFile.path, mimeType: 'text/plain'),
    ], context: mounted ? context : null);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _hasTriedToSave = true;
        });
      }
    });
  }

  Future<void> _saveKeys() async {
    Navigator.of(context).pop();
    if (_recoveryKeyFile.existsSync()) {
      await _recoveryKeyFile.delete();
    }
    widget.onDone!();
  }
}
