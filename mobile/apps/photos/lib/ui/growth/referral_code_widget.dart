import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/models/user_details.dart";
import "package:photos/service_locator.dart";
import "package:photos/utils/dialog_util.dart";
import "package:rive/rive.dart" as rive;

class ReferralCodeWidget extends StatefulWidget {
  final String code;
  final UserDetails userDetails;
  final ValueChanged<String> onCodeChanged;

  const ReferralCodeWidget({
    required this.code,
    required this.userDetails,
    required this.onCodeChanged,
    super.key,
  });

  @override
  State<ReferralCodeWidget> createState() => _ReferralCodeWidgetState();
}

class _ReferralCodeWidgetState extends State<ReferralCodeWidget> {
  final Logger _logger = Logger("ReferralCodeWidget");
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final rive.FileLoader _artworkLoader;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.code);
    _focusNode = FocusNode()..addListener(_handleFocusChange);
    _artworkLoader = rive.FileLoader.fromAsset(
      "assets/referral_card.riv",
      riveFactory: rive.Factory.flutter,
    );
  }

  @override
  void didUpdateWidget(covariant ReferralCodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code && !_isEditing) {
      _controller.text = widget.code;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    _artworkLoader.dispose();
    super.dispose();
  }

  void _handleTextChanged(String _) {
    setState(() {
      _errorText = null;
    });
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _isEditing && !_isSaving) {
      _cancelEditing();
    }
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _errorText = null;
      _controller.text = widget.code;
    });
  }

  String get _normalizedInput => _controller.text.trim().toUpperCase();

  bool get _canSave {
    final input = _normalizedInput;
    return !_isSaving &&
        _errorText == null &&
        input.length >= 4 &&
        input != widget.code.trim().toUpperCase();
  }

  void _handleEditTap() {
    final userDetails = widget.userDetails;
    if (userDetails.isPartOfFamily() && !userDetails.isFamilyAdmin()) {
      showInfoDialog(
        context,
        title: context.strings.error,
        body: context.strings.onlyFamilyAdminCanChangeCode(
          familyAdminEmail: userDetails.familyData!.members!
              .firstWhere((element) => element.isAdmin)
              .email,
        ),
        icon: Icons.error,
      );
      return;
    }
    setState(() {
      _isEditing = true;
      _errorText = null;
      _controller
        ..text = widget.code
        ..selection = TextSelection.collapsed(offset: widget.code.length);
    });
  }

  Future<void> _saveCode() async {
    if (!_canSave) {
      return;
    }
    final newCode = _normalizedInput;
    setState(() {
      _isSaving = true;
    });
    try {
      await storageBonusService.updateCode(newCode);
      if (!mounted) {
        return;
      }
      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      _focusNode.unfocus();
      widget.onCodeChanged(newCode);
    } catch (e, s) {
      _logger.severe("Failed to update code", e, s);
      if (!mounted) {
        return;
      }
      final statusCode = e is DioException ? e.response?.statusCode : null;
      if (statusCode == 400 || statusCode == 429) {
        setState(() {
          _isSaving = false;
          _errorText = statusCode == 400
              ? context.strings.unavailableReferralCode
              : context.strings.codeChangeLimitReached;
        });
        _focusNode.requestFocus();
        return;
      }
      await showGenericErrorDialog(context: context, error: e);
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        _focusNode.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CenteredConstrainedComponent(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: width,
              color: context.componentColors.primary,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [_artwork(width, width / 341), _codePanel(width)],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _artwork(double width, double scale) {
    return SizedBox(
      width: width,
      height: 124 * scale,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 213 * scale,
            child: Image.asset(
              "assets/referral_card_lines.png",
              fit: BoxFit.fill,
              excludeFromSemantics: true,
            ),
          ),
          Positioned.fill(
            child: ExcludeSemantics(
              child: rive.RiveWidgetBuilder(
                fileLoader: _artworkLoader,
                builder: (BuildContext context, rive.RiveState state) {
                  if (state is rive.RiveLoaded) {
                    return Transform.translate(
                      offset: Offset(0, 32 * scale),
                      child: Transform.scale(
                        scale: 1.27,
                        alignment: Alignment.bottomRight,
                        child: rive.RiveWidget(
                          controller: state.controller,
                          fit: rive.Fit.cover,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codePanel(double width) {
    final colors = context.componentColors;
    return Container(
      width: width,
      color: const Color(0xFF0F0F0F),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 89),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(colors),
                  const SizedBox(height: Spacing.sm),
                  _codeArea(colors),
                ],
              ),
            ),
          ),
          Positioned(right: 0, bottom: 0, child: _action(colors)),
        ],
      ),
    );
  }

  Widget _label(ColorTokens colors) {
    final labelText = _errorText ?? context.strings.yourReferralCode;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        labelText.toUpperCase(),
        maxLines: 1,
        semanticsLabel: labelText,
        style: TextStyles.mini.copyWith(
          fontSize: 8,
          letterSpacing: 1.8,
          color: _errorText != null
              ? colors.warning
              : colors.specialWhite.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  Widget _codeArea(ColorTokens colors) {
    final codeStyle = TextStyles.display2.copyWith(color: colors.specialWhite);
    if (!_isEditing) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(widget.code, maxLines: 1, style: codeStyle),
      );
    }
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      readOnly: _isSaving,
      maxLines: 1,
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp("[a-zA-Z0-9]")),
        LengthLimitingTextInputFormatter(20),
      ],
      style: codeStyle,
      cursorColor: colors.primary,
      cursorWidth: 2,
      onChanged: _handleTextChanged,
      onEditingComplete: _saveCode,
      onTapOutside: (_) => _focusNode.unfocus(),
      decoration: const InputDecoration(
        isDense: true,
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
      ),
    );
  }

  Widget _action(ColorTokens colors) {
    final l10n = context.strings;
    final enabled = _isEditing ? _canSave : true;
    final actionLabel = _isSaving
        ? l10n.saving
        : _isEditing
        ? l10n.saveCode
        : l10n.edit;
    return TextFieldTapRegion(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: actionLabel,
        child: Tooltip(
          message: actionLabel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _isEditing ? (_canSave ? _saveCode : null) : _handleEditTap,
            child: SizedBox.square(
              dimension: 48,
              child: Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  width: 41,
                  height: 41,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.specialWhiteOverlay,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(21),
                      bottomRight: Radius.circular(21),
                    ),
                  ),
                  child: _isSaving
                      ? EnteLoadingWidget(
                          color: colors.specialWhite,
                          size: 16,
                          padding: 0,
                        )
                      : HugeIcon(
                          icon: _isEditing
                              ? HugeIcons.strokeRoundedTick02
                              : HugeIcons.strokeRoundedEdit03,
                          color: enabled
                              ? colors.specialWhite
                              : colors.specialWhite.withValues(alpha: 0.4),
                          size: 22,
                          strokeWidth: 1.7,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
