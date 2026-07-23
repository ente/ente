import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/account/two_factor.dart";
import 'package:photos/services/account/user_service.dart';
import "package:photos/ui/components/alert_bottom_sheet.dart";

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
  final _recoveryKeyController = TextEditingController();
  String _recoveryKey = '';

  @override
  void dispose() {
    _recoveryKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final isFormValid = _recoveryKey.isNotEmpty;

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
          AppLocalizations.of(context).recoverAccount,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        centerTitle: true,
      ),
      body: _getBody(),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ButtonComponent(
          key: const ValueKey("recover2FAButton"),
          label: AppLocalizations.of(context).recover,
          isDisabled: !isFormValid,
          onTap: isFormValid
              ? () async {
                  FocusScope.of(context).unfocus();
                  await UserService.instance.removeTwoFactor(
                    context,
                    widget.type,
                    widget.sessionID,
                    _recoveryKeyController.text,
                    widget.encryptedSecret,
                    widget.secretDecryptionNonce,
                  );
                }
              : null,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _getBody() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 24),
            TextInputComponent(
              label: AppLocalizations.of(context).recoveryKey,
              hintText: AppLocalizations.of(context).enterYourRecoveryKey,
              controller: _recoveryKeyController,
              autocorrect: false,
              keyboardType: TextInputType.multiline,
              minLines: 4,
              maxLines: null,
              onChanged: (value) {
                final hasKey = value.isNotEmpty;
                if ((_recoveryKey.isNotEmpty) != hasKey) {
                  setState(() {
                    _recoveryKey = value;
                  });
                } else {
                  _recoveryKey = value;
                }
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ButtonComponent(
                label: AppLocalizations.of(context).noRecoveryKey,
                variant: ButtonComponentVariant.link,
                size: ButtonComponentSize.small,
                shouldSurfaceExecutionStates: false,
                onTap: () async {
                  // ignore: unawaited_futures
                  showAlertBottomSheet(
                    context,
                    title: AppLocalizations.of(context).contactSupport,
                    message: AppLocalizations.of(
                      context,
                    ).dropSupportEmail(supportEmail: "support@ente.com"),
                    assetPath: 'assets/warning-grey.png',
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
