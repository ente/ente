import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/gateways/storage_bonus/models/storage_bonus.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/user_details.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/growth/code_success_screen.dart";

Future<bool?> showApplyCodeSheet(
  BuildContext context, {
  required ReferralView referralView,
  required UserDetails userDetails,
}) {
  return showBottomSheetComponent<bool>(
    context: context,
    builder: (_) => BottomSheetComponent(
      title: AppLocalizations.of(context).applyCodeTitle,
      isKeyboardAware: true,
      content: _ApplyCodeContent(
        referralView: referralView,
        userDetails: userDetails,
      ),
    ),
  );
}

class _ApplyCodeContent extends StatefulWidget {
  final ReferralView referralView;
  final UserDetails userDetails;

  const _ApplyCodeContent({
    required this.referralView,
    required this.userDetails,
  });

  @override
  State<_ApplyCodeContent> createState() => _ApplyCodeContentState();
}

class _ApplyCodeContentState extends State<_ApplyCodeContent> {
  late TextEditingController _controller;
  late FocusNode _codeFocusNode;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _codeFocusNode = FocusNode();
    _controller.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 30), () {
        if (mounted) {
          _codeFocusNode.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _errorMessage = null;
    });
  }

  bool get _isValid => _controller.text.trim().length >= 4;

  Future<void> _applyCode() async {
    final code = _controller.text.trim();
    if (code.length < 4) {
      return;
    }

    setState(() => _errorMessage = null);

    try {
      await storageBonusService.applyCode(code);
      if (mounted) {
        Navigator.of(context).pop(true);
        // Navigate to success screen
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                CodeSuccessScreen(widget.referralView, widget.userDetails),
          ),
        );
      }
    } catch (e) {
      Logger("ApplyCodeSheet").severe("Failed to apply code", e);
      if (mounted) {
        String errorMessage = AppLocalizations.of(context).failedToApplyCode;
        if (e is DioException &&
            e.response != null &&
            e.response!.data != null) {
          final code = e.response!.data["code"];
          if (code == "INVALID_CODE") {
            errorMessage = AppLocalizations.of(context).invalidReferralCode;
          } else if (code != null) {
            errorMessage =
                "${AppLocalizations.of(context).failedToApplyCode}: $code";
          }
        }
        setState(() {
          _errorMessage = errorMessage;
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
          focusNode: _codeFocusNode,
          inputFormatters: [UpperCaseTextFormatter()],
          textCapitalization: TextCapitalization.characters,
          hintText: l10n.enterReferralCode,
          message: _errorMessage ?? l10n.enterCodeDescription,
          messageType: _errorMessage == null
              ? TextInputComponentMessageType.helper
              : TextInputComponentMessageType.error,
          autocorrect: false,
        ),
        const SizedBox(height: Spacing.lg),
        ButtonComponent(
          label: l10n.apply,
          isDisabled: !_isValid,
          onTap: _applyCode,
        ),
      ],
    );
  }
}
