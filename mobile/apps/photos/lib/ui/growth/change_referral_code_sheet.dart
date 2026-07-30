import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/utils/dialog_util.dart";

Future<bool?> showChangeReferralCodeSheet(
  BuildContext context, {
  required String currentCode,
  required VoidCallback onCodeChanged,
}) {
  return showBottomSheetComponent<bool>(
    context: context,
    builder: (_) => BottomSheetComponent(
      title: AppLocalizations.of(context).changeYourReferralCode,
      isKeyboardAware: true,
      content: _ChangeReferralCodeContent(
        currentCode: currentCode,
        onCodeChanged: onCodeChanged,
      ),
    ),
  );
}

class _ChangeReferralCodeContent extends StatefulWidget {
  final String currentCode;
  final VoidCallback onCodeChanged;

  const _ChangeReferralCodeContent({
    required this.currentCode,
    required this.onCodeChanged,
  });

  @override
  State<_ChangeReferralCodeContent> createState() =>
      _ChangeReferralCodeContentState();
}

class _ChangeReferralCodeContentState
    extends State<_ChangeReferralCodeContent> {
  late TextEditingController _controller;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentCode);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _errorMessage = null;
    });
  }

  bool get _hasChanges =>
      _controller.text.trim().length >= 4 &&
      _controller.text.trim() != widget.currentCode;

  Future<void> _saveCode() async {
    final newCode = _controller.text.trim();
    if (newCode.isEmpty || newCode == widget.currentCode) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await storageBonusService.updateCode(newCode);
      widget.onCodeChanged();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e, s) {
      Logger("ChangeReferralCodeSheet").severe("Failed to update code", e, s);
      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          setState(() {
            _errorMessage = AppLocalizations.of(
              context,
            ).unavailableReferralCode;
          });
        } else if (e.response?.statusCode == 429) {
          setState(() {
            _errorMessage = AppLocalizations.of(context).codeChangeLimitReached;
          });
        } else {
          if (mounted) {
            await showGenericErrorDialog(context: context, error: e);
          }
        }
      } else {
        if (mounted) {
          await showGenericErrorDialog(context: context, error: e);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextInputComponent(
          controller: _controller,
          textCapitalization: TextCapitalization.characters,
          hintText: l10n.enterCode,
          message: _errorMessage ?? l10n.referralCodeHint,
          messageType: _errorMessage == null
              ? TextInputComponentMessageType.helper
              : TextInputComponentMessageType.error,
          autocorrect: false,
        ),
        const SizedBox(height: Spacing.lg),
        ButtonComponent(
          label: l10n.saveCode,
          isDisabled: _isLoading || !_hasChanges,
          shouldShowSuccessState: false,
          onTap: _saveCode,
        ),
      ],
    );
  }
}
