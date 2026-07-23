import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import "package:photos/l10n/l10n.dart";
import 'package:photos/services/account/user_service.dart';
import 'package:photos/utils/email_util.dart';

Future<void> showChangeEmailBottomSheet(BuildContext context) {
  return showBottomSheetComponent<void>(
    context: context,
    builder: (_) => const _ChangeEmailBottomSheet(),
  );
}

class _ChangeEmailBottomSheet extends StatefulWidget {
  const _ChangeEmailBottomSheet();

  @override
  State<_ChangeEmailBottomSheet> createState() =>
      _ChangeEmailBottomSheetState();
}

class _ChangeEmailBottomSheetState extends State<_ChangeEmailBottomSheet> {
  final _emailController = TextEditingController();
  bool _hasEmail = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BottomSheetComponent(
      title: l10n.enterYourNewEmailAddress,
      isKeyboardAware: true,
      content: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextInputComponent(
              controller: _emailController,
              hintText: l10n.email,
              autofocus: true,
              isClearable: true,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textCapitalization: TextCapitalization.none,
              onSubmit: (_) => _verify(),
              onChanged: (_) {
                final hasEmail = _emailController.text.trim().isNotEmpty;
                if (_hasEmail == hasEmail) {
                  return;
                }
                setState(() {
                  _hasEmail = hasEmail;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        ButtonComponent(
          label: l10n.verify,
          isDisabled: !_hasEmail,
          onTap: () => _verify(),
        ),
      ],
    );
  }

  Future<void> _verify() async {
    final l10n = context.l10n;
    final email = _emailController.text.trim();

    if (!isValidEmail(email)) {
      await showErrorBottomSheetComponent<void>(
        context: context,
        title: l10n.invalidEmailAddress,
        message: l10n.enterValidEmail,
        illustration: Image.asset('assets/warning-grey.png'),
      );
      return;
    }

    await UserService.instance.sendOtt(context, email, isChangeEmail: true);
  }
}
