import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import "package:photos/core/event_bus.dart";
import "package:photos/events/clear_and_unfocus_search_bar_event.dart";
import "package:photos/theme/ente_theme.dart";

class SearchSuffixIcon extends StatefulWidget {
  final bool shouldShowSpinner;
  final bool showClearButton;
  const SearchSuffixIcon(
    this.shouldShowSpinner, {
    required this.showClearButton,
    super.key,
  });

  @override
  State<SearchSuffixIcon> createState() => _SearchSuffixIconState();
}

class _SearchSuffixIconState extends State<SearchSuffixIcon> {
  static const double _suffixContainerSize = 24;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final componentColors = context.componentColors;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 175),
      child: widget.shouldShowSpinner
          ? SizedBox(
              width: _suffixContainerSize,
              height: _suffixContainerSize,
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.strokeMuted,
                  ),
                ),
              ),
            )
          : widget.showClearButton
          ? IconButton(
              splashRadius: 1,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: _suffixContainerSize,
                height: _suffixContainerSize,
              ),
              alignment: Alignment.centerRight,
              visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
              onPressed: () {
                Bus.instance.fire(ClearAndUnfocusSearchBar());
              },
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedCancel01,
                color: componentColors.textLight,
                size: 18,
              ),
            )
          : const SizedBox(
              width: _suffixContainerSize,
              height: _suffixContainerSize,
            ),
    );
  }
}
