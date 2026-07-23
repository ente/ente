import 'package:ente_accounts/ente_accounts.dart';
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/alert_bottom_sheet.dart';
import 'package:ente_ui/components/base_bottom_sheet.dart';
import 'package:ente_ui/components/buttons/gradient_button.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:flutter/material.dart';

class ChangeEmailDialog extends StatefulWidget {
  const ChangeEmailDialog({super.key});

  @override
  State<ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<ChangeEmailDialog> {
  final _emailController = TextEditingController();
  String _email = '';
  bool _emailIsValid = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(() {
      setState(() {
        _email = _emailController.text.trim();
        _emailIsValid = isValidEmail(_email);
      });
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _emailController,
            decoration: InputDecoration(
              fillColor: _emailIsValid
                  ? colorScheme.primary700.withValues(alpha: 0.2)
                  : colorScheme.backdropBase,
              filled: true,
              hintText: context.strings.enterNewEmailHint,
              hintStyle: TextStyle(color: colorScheme.textMuted),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: _emailIsValid
                  ? Icon(Icons.check, size: 20, color: colorScheme.primary700)
                  : null,
            ),
            style: textTheme.body.copyWith(color: colorScheme.textBase),
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofocus: true,
            onFieldSubmitted: (_) => _handleSubmit(),
          ),
          const SizedBox(height: 24),
          GradientButton(
            text: context.strings.verify,
            onTap: _emailIsValid ? _handleSubmit : null,
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_emailIsValid) {
      await showAlertBottomSheet(
        context,
        title: context.strings.invalidEmailTitle,
        message: context.strings.invalidEmailMessage,
        assetPath: 'assets/warning-grey.png',
      );
      return;
    }

    await UserService.instance.sendOtt(context, _email, isChangeEmail: true);
  }
}

Future<void> showChangeEmailDialog(BuildContext context) {
  return showBaseBottomSheet(
    context,
    title: context.strings.changeEmail,
    headerSpacing: 20,
    isKeyboardAware: true,
    child: const ChangeEmailDialog(),
  );
}
