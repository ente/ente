import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/ui/account/password_entry_page.dart';
import "package:photos/ui/components/alert_bottom_sheet.dart";
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/utils/dialog_util.dart';

class RecoveryPage extends StatefulWidget {
  const RecoveryPage({super.key});

  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  final _recoveryKeyController = TextEditingController();

  @override
  void dispose() {
    _recoveryKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final isFormValid = _recoveryKeyController.text.isNotEmpty;

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
          key: const ValueKey("recoveryButton"),
          label: AppLocalizations.of(context).logInLabel,
          isDisabled: !isFormValid,
          onTap: isFormValid ? _onRecoverPressed : null,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _getBody() {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 12),
          TextInputComponent(
            label: AppLocalizations.of(context).recoveryKey,
            hintText: AppLocalizations.of(context).enterYourRecoveryKey,
            controller: _recoveryKeyController,
            keyboardType: TextInputType.multiline,
            maxLines: null,
            minLines: 5,
            autocorrect: false,
            onChanged: (value) {
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
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
                  title: AppLocalizations.of(context).sorry,
                  message: AppLocalizations.of(
                    context,
                  ).noRecoveryKeyNoDecryption,
                  assetPath: 'assets/warning-grey.png',
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onRecoverPressed() async {
    FocusScope.of(context).unfocus();
    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).decrypting,
    );
    await dialog.show();
    try {
      await Configuration.instance.recover(_recoveryKeyController.text.trim());
      await dialog.hide();
      if (!mounted) return;
      showShortToast(context, AppLocalizations.of(context).recoverySuccessful);
      if (!mounted) return;
      // ignore: unawaited_futures
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return const PopScope(
              canPop: false,
              child: PasswordEntryPage(mode: PasswordEntryMode.reset),
            );
          },
        ),
      );
    } catch (e) {
      await dialog.hide();
      if (!mounted) return;
      String errMessage = AppLocalizations.of(context).incorrectRecoveryKeyBody;
      if (e is AssertionError) {
        errMessage = '$errMessage : ${e.message}';
      }
      if (!mounted) return;
      // ignore: unawaited_futures
      showAlertBottomSheet(
        context,
        title: AppLocalizations.of(context).incorrectRecoveryKeyTitle,
        message: errMessage,
        assetPath: 'assets/warning-grey.png',
      );
    }
  }
}
