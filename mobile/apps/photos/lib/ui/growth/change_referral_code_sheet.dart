import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/base_bottom_sheet.dart";
import "package:photos/utils/dialog_util.dart";

Future<bool?> showChangeReferralCodeSheet(
  BuildContext context, {
  required String currentCode,
  required VoidCallback onCodeChanged,
}) {
  return showBaseBottomSheet<bool>(
    context,
    title: AppLocalizations.of(context).changeYourReferralCode,
    headerSpacing: 20,
    child: _ChangeReferralCodeContent(
      currentCode: currentCode,
      onCodeChanged: onCodeChanged,
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
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final inputBackgroundColor = isDarkMode
        ? const Color(0xFF1C1C1C)
        : const Color(0xFFFAFAFA);

    const greenColor = Color(0xFF08C225);
    const warningRedColor = Color(0xFFF63A3A);
    final helperTextColor = _errorMessage != null
        ? warningRedColor
        : colorScheme.textMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text input field
        Container(
          decoration: BoxDecoration(
            color: inputBackgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.characters,
            style: textTheme.body,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 20,
              ),
              hintText: AppLocalizations.of(context).enterCode,
              hintStyle: textTheme.body.copyWith(color: colorScheme.textMuted),
            ),
          ),
        ),
        const SizedBox(height: 9),
        // Warning/helper text
        Text(
          _errorMessage ?? AppLocalizations.of(context).referralCodeHint,
          style: textTheme.mini.copyWith(color: helperTextColor),
        ),
        const SizedBox(height: 20),
        // Save button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading || !_hasChanges ? null : _saveCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: _hasChanges ? greenColor : colorScheme.fillMuted,
              foregroundColor: Colors.white,
              disabledBackgroundColor: colorScheme.fillMuted,
              disabledForegroundColor: colorScheme.textMuted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.textMuted,
                    ),
                  )
                : Text(
                    AppLocalizations.of(context).saveCode,
                    style: textTheme.bodyBold.copyWith(
                      color: _hasChanges ? Colors.white : colorScheme.textMuted,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
