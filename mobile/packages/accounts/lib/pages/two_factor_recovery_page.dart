import 'package:ente_accounts/ente_accounts.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/buttons/dynamic_fab.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:ente_utils/email_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class TwoFactorRecoveryPage extends StatefulWidget {
  final String sessionID;
  final String encryptedSecret;
  final String secretDecryptionNonce;
  final TwoFactorType type;

  const TwoFactorRecoveryPage(
    this.type,
    this.sessionID,
    this.encryptedSecret,
    this.secretDecryptionNonce, {
    super.key,
  });

  @override
  State<TwoFactorRecoveryPage> createState() => _TwoFactorRecoveryPageState();
}

class _TwoFactorRecoveryPageState extends State<TwoFactorRecoveryPage> {
  final _recoveryKey = TextEditingController();

  Future<void> _onRecover() async {
    await UserService.instance.removeTwoFactor(
      context,
      widget.type,
      widget.sessionID,
      _recoveryKey.text,
      widget.encryptedSecret,
      widget.secretDecryptionNonce,
    );
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
        isFormValid: _recoveryKey.text.isNotEmpty,
        buttonText: context.strings.recover,
        onPressedFunction: _onRecover,
      ),
      floatingActionButtonLocation: fabLocation(),
      floatingActionButtonAnimator: NoScalingAnimation(),
    );
  }

  Widget _getBody() {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return SafeArea(
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
                      context.strings.recoveryKey,
                      style: textTheme.bodyBold.copyWith(
                        color: colorScheme.textBase,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      decoration: InputDecoration(
                        fillColor: colorScheme.backdropBase,
                        filled: true,
                        hintText: context.strings.enterRecoveryKeyHint,
                        hintStyle: TextStyle(color: colorScheme.textMuted),
                        contentPadding: const EdgeInsets.all(16),
                        border: OutlineInputBorder(
                          borderSide: BorderSide.none,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide.none,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      style: textTheme.body.copyWith(
                        color: colorScheme.textBase,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                      controller: _recoveryKey,
                      autofocus: false,
                      autocorrect: false,
                      keyboardType: TextInputType.multiline,
                      maxLines: 4,
                      minLines: 4,
                      onChanged: (_) {
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () async {
                            await sendEmail(context, to: "support@ente.com");
                          },
                          child: Text(
                            context.strings.noRecoveryKeyTitle,
                            style: textTheme.small.copyWith(
                              color: colorScheme.primary700,
                              decoration: TextDecoration.underline,
                              decorationColor: colorScheme.primary700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
