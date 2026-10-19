import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:photos/core/configuration.dart';
import "package:photos/ui/account/onboarding_page_scaffold.dart";
import 'package:photos/ui/account/password_entry_page.dart';
import "package:photos/ui/components/alert_bottom_sheet.dart";
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/utils/dialog_util.dart';

class RecoveryPage extends StatefulWidget {
  final bool isForgotPassword;

  const RecoveryPage({this.isForgotPassword = false, super.key});

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
    final isFormValid = _recoveryKeyController.text.isNotEmpty;

    return OnboardingPageScaffold(
      title: widget.isForgotPassword
          ? context.strings.forgotPassword
          : context.strings.recoverAccount,
      illustration: OnboardingIllustration.forgotPassword,
      body: _getBody(),
      actions: [
        ButtonComponent(
          key: const ValueKey("recoveryButton"),
          label: context.strings.logInLabel,
          shouldShowSuccessState: false,
          isDisabled: !isFormValid,
          onTap: isFormValid ? _onRecoverPressed : null,
        ),
      ],
    );
  }

  Widget _getBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextInputComponent(
          label: context.strings.recoveryKey,
          hintText: context.strings.enterYourRecoveryKey,
          controller: _recoveryKeyController,
          keyboardType: TextInputType.multiline,
          maxLines: null,
          minLines: 5,
          autocorrect: false,
          onChanged: (value) {
            setState(() {});
          },
        ),
        const SizedBox(height: Spacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: ButtonComponent(
            label: context.strings.forgotRecoveryKey,
            variant: ButtonComponentVariant.link,
            size: ButtonComponentSize.small,
            shouldSurfaceExecutionStates: false,
            onTap: _showNoRecoveryKeySheet,
          ),
        ),
      ],
    );
  }

  Future<void> _showNoRecoveryKeySheet() {
    return showBottomSheetComponent<void>(
      context: context,
      builder: (_) => BottomSheetComponent(
        title: context.strings.sorry,
        message: context.strings.noRecoveryKeyNoDecryption,
        illustration: Image.asset("assets/warning-red.png"),
        actions: [
          ButtonComponent(
            label: context.strings.ok,
            shouldSurfaceExecutionStates: false,
            dismissModalOnSuccess: true,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Future<void> _onRecoverPressed() async {
    FocusScope.of(context).unfocus();
    final dialog = createProgressDialog(context, context.strings.decrypting);
    await dialog.show();
    try {
      await Configuration.instance.recover(_recoveryKeyController.text.trim());
      await dialog.hide();
      if (!mounted) return;
      showShortToast(context, context.strings.recoverySuccessful);
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
      String errMessage = context.strings.incorrectRecoveryKeyBody;
      if (e is AssertionError) {
        errMessage = '$errMessage : ${e.message}';
      }
      if (!mounted) return;
      // ignore: unawaited_futures
      showAlertBottomSheet(
        context,
        title: context.strings.incorrectRecoveryKeyTitle,
        message: errMessage,
        assetPath: 'assets/warning-grey.png',
      );
    }
  }
}
