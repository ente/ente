import "package:ente_components/ente_components.dart";
import "package:ente_icons/ente_icons.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/social/comment.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/social/widgets/reply_preview_widget.dart";

enum SendButtonState { idle, sending, error }

class CommentInputWidget extends StatefulWidget {
  final Comment? replyingTo;
  final User? replyingToUser;
  final int currentUserID;
  final VoidCallback? onDismissReply;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final SendButtonState sendState;

  const CommentInputWidget({
    this.replyingTo,
    this.replyingToUser,
    required this.currentUserID,
    this.onDismissReply,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.sendState = SendButtonState.idle,
    super.key,
  });

  @override
  State<CommentInputWidget> createState() => _CommentInputWidgetState();
}

class _CommentInputWidgetState extends State<CommentInputWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _showReplyPreview = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _showReplyPreview = widget.replyingTo != null;
    if (_showReplyPreview) {
      _animationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(CommentInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.replyingTo != null && oldWidget.replyingTo == null) {
      setState(() => _showReplyPreview = true);
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    _animationController.reverse().then((_) {
      if (mounted) {
        setState(() => _showReplyPreview = false);
        widget.onDismissReply?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = getEnteColorScheme(context);
    final componentColors = context.componentColors;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textFieldFillColor = isDarkMode
        ? const Color(0xFF212121)
        : const Color(0xFFF3F3F3);
    final textFieldBorderColor = isDarkMode
        ? const Color(0xFF0E0E0E)
        : const Color(0xFF000000).withValues(alpha: 0.02);

    return Container(
      padding: const EdgeInsets.only(bottom: 20, left: 18, right: 18, top: 20),
      color: isDarkMode
          ? const Color(0xFF0E0E0E)
          : colorScheme.backgroundElevated,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: textFieldFillColor,
            border: Border.all(
              color: textFieldBorderColor,
              width: 2,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_showReplyPreview && widget.replyingToUser != null)
                SizeTransition(
                  sizeFactor: _animation,
                  axisAlignment: -1.0,
                  child: FadeTransition(
                    opacity: _animation,
                    child: ReplyPreviewWidget(
                      replyingTo: widget.replyingTo!,
                      replyingToUser: widget.replyingToUser!,
                      currentUserID: widget.currentUserID,
                      onDismiss: _handleDismiss,
                    ),
                  ),
                ),
              TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                inputFormatters: [LengthLimitingTextInputFormatter(500)],
                minLines: 1,
                maxLines: widget.replyingTo != null ? 4 : 8,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyles.body.copyWith(
                  color: componentColors.textBase,
                ),
                decoration: InputDecoration(
                  hintText: l10n.commentHint,
                  hintStyle: TextStyles.body.copyWith(
                    color: componentColors.textLighter,
                  ),
                  border: InputBorder.none,
                  filled: true,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  suffixIcon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeOut,
                    transitionBuilder: (child, animation) {
                      final curvedAnimation = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeInOutExpo,
                      );
                      final scale = Tween<double>(
                        begin: 0.5,
                        end: 1.0,
                      ).animate(curvedAnimation);
                      return FadeTransition(
                        opacity: curvedAnimation,
                        child: ScaleTransition(scale: scale, child: child),
                      );
                    },
                    child: switch (widget.sendState) {
                      SendButtonState.sending => const Padding(
                        key: ValueKey('loading'),
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: EnteLoadingWidget(size: 20, padding: 0),
                        ),
                      ),
                      SendButtonState.error => Padding(
                        key: const ValueKey('error'),
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.error_outline,
                          color: colorScheme.warning500,
                          size: 24,
                        ),
                      ),
                      SendButtonState.idle => IconButton(
                        key: const ValueKey('send'),
                        onPressed: widget.onSend,
                        icon: Icon(
                          EnteIcons.sendStroke,
                          color: colorScheme.textBase.withValues(alpha: 0.8),
                          size: 24,
                        ),
                      ),
                    },
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
