import "dart:async";
import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";
import "package:photos/ui/sharing/share_components.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";
import "package:photos/ui/sharing/widgets/sharing_role.dart";

class SelectedRecipientChips extends StatefulWidget {
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
  State<SelectedRecipientChips> createState() => _SelectedRecipientChipsState();
}

class _SelectedRecipientChipsState extends State<SelectedRecipientChips> {
  late final _displayedSuggestions = List<UserSuggestion>.of(
    widget.suggestions,
  );

  @override
  void didUpdateWidget(covariant SelectedRecipientChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final suggestion in widget.suggestions) {
      final index = _displayedSuggestions.indexWhere(
        (displayed) =>
            normalizedSharingEmail(displayed.email) ==
            normalizedSharingEmail(suggestion.email),
      );
      if (index == -1) {
        _displayedSuggestions.add(suggestion);
      } else {
        _displayedSuggestions[index] = suggestion;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chipExtent = SelectedRecipientChips.chipExtent(context);
    final maxViewportHeight =
        widget.maxVisibleRows * chipExtent +
        (widget.maxVisibleRows - 1) * Spacing.sm;

    return AnimatedSize(
      duration: Motion.standard,
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.topStart,
      child: _displayedSuggestions.isEmpty
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
                      controller: widget.scrollController,
                      child: SingleChildScrollView(
                        key: const ValueKey("selected-people-scroll"),
                        controller: widget.scrollController,
                        primary: false,
                        padding: const EdgeInsetsDirectional.only(
                          end: Spacing.md,
                        ),
                        child: Wrap(
                          spacing: Spacing.sm,
                          runSpacing: Spacing.sm,
                          children: [
                            for (final suggestion in _displayedSuggestions)
                              SelectedPersonChip(
                                key: ValueKey(
                                  suggestion.email.trim().toLowerCase(),
                                ),
                                suggestion: suggestion,
                                isRemoving: !_isSelected(suggestion),
                                onRemovalComplete: () =>
                                    _finishRemoval(suggestion),
                                onRemove: widget.onRemove == null
                                    ? null
                                    : () => _remove(suggestion),
                                onLongPress: widget.onLongPress == null
                                    ? null
                                    : () => widget.onLongPress!(suggestion),
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

  bool _isSelected(UserSuggestion suggestion) => widget.suggestions.any(
    (selected) =>
        normalizedSharingEmail(selected.email) ==
        normalizedSharingEmail(suggestion.email),
  );

  void _remove(UserSuggestion suggestion) {
    if (_isSelected(suggestion)) {
      widget.onRemove!(suggestion);
    }
  }

  void _finishRemoval(UserSuggestion suggestion) {
    if (_isSelected(suggestion)) return;
    setState(() {
      _displayedSuggestions.removeWhere(
        (displayed) =>
            normalizedSharingEmail(displayed.email) ==
            normalizedSharingEmail(suggestion.email),
      );
    });
  }
}

class SelectedPersonChip extends StatefulWidget {
  const SelectedPersonChip({
    super.key,
    required this.suggestion,
    required this.isRemoving,
    required this.onRemovalComplete,
    this.onRemove,
    this.onLongPress,
  });

  final UserSuggestion suggestion;
  final bool isRemoving;
  final VoidCallback onRemovalComplete;
  final VoidCallback? onRemove;
  final VoidCallback? onLongPress;

  @override
  State<SelectedPersonChip> createState() => _SelectedPersonChipState();
}

class _SelectedPersonChipState extends State<SelectedPersonChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;

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
  void didUpdateWidget(covariant SelectedPersonChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRemoving == oldWidget.isRemoving) return;
    if (widget.isRemoving) {
      unawaited(_animateRemoval());
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _animateRemoval() async {
    await _controller.reverse();
    if (mounted && widget.isRemoving) {
      widget.onRemovalComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = resolveSuggestionDisplayName(widget.suggestion);
    return IgnorePointer(
      ignoring: widget.isRemoving,
      child: ExcludeSemantics(
        excluding: widget.isRemoving,
        child: AnimatedBuilder(
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
                      onTap: widget.onRemove,
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
        ),
      ),
    );
  }
}
