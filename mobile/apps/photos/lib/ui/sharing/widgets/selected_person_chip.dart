import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";
import "package:photos/ui/sharing/share_components.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";

class SelectedRecipientChips extends StatelessWidget {
  const SelectedRecipientChips({
    super.key,
    required this.suggestions,
    required this.scrollController,
    this.onRemove,
    this.onLongPress,
    this.maxVisibleRows = 3,
  });

  static double chipExtent(BuildContext context) {
    return FilterChipComponent.heightForTextScale(context);
  }

  final List<UserSuggestion> suggestions;
  final ValueChanged<UserSuggestion>? onRemove;
  final ValueChanged<UserSuggestion>? onLongPress;
  final ScrollController scrollController;
  final int maxVisibleRows;

  @override
  Widget build(BuildContext context) {
    final chipExtent = SelectedRecipientChips.chipExtent(context);
    final maxViewportHeight =
        maxVisibleRows * chipExtent + (maxVisibleRows - 1) * Spacing.sm;

    return AnimatedSize(
      duration: Motion.standard,
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.topStart,
      child: suggestions.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: Spacing.xl),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewportMaxHeight = constraints.hasBoundedHeight
                      ? math.min(maxViewportHeight, constraints.maxHeight)
                      : maxViewportHeight;
                  if (viewportMaxHeight <= 0) {
                    return const SizedBox.shrink();
                  }
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                      maxHeight: viewportMaxHeight,
                    ),
                    child: shareScrollbar(
                      context,
                      key: const ValueKey("selected-people-scrollbar"),
                      controller: scrollController,
                      child: SingleChildScrollView(
                        key: const ValueKey("selected-people-scroll"),
                        controller: scrollController,
                        primary: false,
                        padding: const EdgeInsetsDirectional.only(
                          end: Spacing.md,
                        ),
                        child: Wrap(
                          spacing: Spacing.sm,
                          runSpacing: Spacing.sm,
                          children: [
                            for (final suggestion in suggestions)
                              SelectedPersonChip(
                                key: ValueKey(
                                  suggestion.email.trim().toLowerCase(),
                                ),
                                suggestion: suggestion,
                                onRemove: onRemove == null
                                    ? null
                                    : () => onRemove!(suggestion),
                                onLongPress: onLongPress == null
                                    ? null
                                    : () => onLongPress!(suggestion),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class SelectedPersonChip extends StatefulWidget {
  const SelectedPersonChip({
    super.key,
    required this.suggestion,
    this.onRemove,
    this.onLongPress,
  });

  final UserSuggestion suggestion;
  final VoidCallback? onRemove;
  final VoidCallback? onLongPress;

  @override
  State<SelectedPersonChip> createState() => _SelectedPersonChipState();
}

class _SelectedPersonChipState extends State<SelectedPersonChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.standard);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _remove() async {
    if (_isRemoving || widget.onRemove == null) {
      return;
    }
    _isRemoving = true;
    await _controller.reverse();
    if (mounted) {
      widget.onRemove!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = resolveSuggestionDisplayName(widget.suggestion);
    return AnimatedBuilder(
      key: ValueKey(
        "selected-person-chip-${widget.suggestion.email.trim().toLowerCase()}",
      ),
      animation: _animation,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: widget.onLongPress,
        child: Container(
          constraints: BoxConstraints(
            minHeight: SelectedRecipientChips.chipExtent(context),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          decoration: BoxDecoration(
            color: context.componentColors.fillLight,
            borderRadius: BorderRadius.circular(Radii.button),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              UserAvatarWidget.suggestion(
                widget.suggestion,
                type: AvatarType.medium,
              ),
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.mini,
                ),
              ),
              if (widget.onRemove != null) ...[
                const SizedBox(width: Spacing.xs),
                GestureDetector(
                  key: ValueKey(
                    "remove-${widget.suggestion.email.trim().toLowerCase()}",
                  ),
                  behavior: HitTestBehavior.opaque,
                  onTap: _remove,
                  child: const Padding(
                    padding: EdgeInsets.all(Spacing.xs),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      size: IconSizes.small,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      builder: (context, child) => Opacity(
        opacity: _animation.value,
        child: Transform.scale(
          scale: 0.96 + 0.04 * _animation.value,
          alignment: AlignmentDirectional.centerStart,
          child: child,
        ),
      ),
    );
  }
}
