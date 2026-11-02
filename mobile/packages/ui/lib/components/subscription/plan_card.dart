import 'dart:ui' show lerpDouble;

import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

class SubscriptionPlanCard extends StatelessWidget {
  const SubscriptionPlanCard({
    super.key,
    required this.value,
    required this.unit,
    required this.includedAllowance,
    required this.price,
    this.isSelected = false,
    this.isFree = false,
    this.badgeLabel,
  });

  static const double height = 96;
  static const double _selectedAllowanceSize = 46.4522;
  static const Color _selectionDepth = Color(0xFF009B18);
  static const Color _selectionStroke = Color(0xFF46E35E);
  static const Color _badgeColor = Color(0xFFFFD525);
  static const Color _badgeHighlight = Color(0xFFFFEFAD);
  static const Color _outline = Color(0xFF171717);

  final String value;
  final String unit;
  final Widget includedAllowance;
  final Widget price;
  final bool isSelected;
  final bool isFree;
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    final selection = isSelected ? 1.0 : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: selection, end: selection),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Motion.slow,
      curve: Curves.easeOutCubic,
      child: _allowance(context),
      builder: (context, progress, child) =>
          _buildCard(context, progress, child!),
    );
  }

  Widget _buildCard(
    BuildContext context,
    double selection,
    Widget allowanceText,
  ) {
    final colors = context.componentColors;
    final hasBadge = badgeLabel != null;
    final textScaler = MediaQuery.textScalerOf(context);
    final background = Color.lerp(colors.fillLight, colors.green, selection)!;
    final baseAllowanceSize = isFree ? 36.9512 : 36.0;
    final visualAllowanceSize = textScaler.scale(
      lerpDouble(baseAllowanceSize, _selectedAllowanceSize, selection)!,
    );
    final topInset = hasBadge ? textScaler.scale(22) : 6 * selection;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final layer in [(16.0, 1.0, 3.0), (17.0, 10.0, 2.0)])
          Positioned.fill(
            top: topInset + (layer.$1 - 22) * selection,
            left: -6 * selection,
            right: -6 * selection,
            bottom: layer.$2 * selection,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _selectionDepth.withValues(alpha: selection),
                  border: Border.all(
                    color: _outline.withValues(alpha: selection),
                    width: layer.$3,
                    strokeAlign: BorderSide.strokeAlignCenter,
                  ),
                  borderRadius: BorderRadius.circular(27),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: topInset, bottom: 16 * selection),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(Radii.button),
              border: Border.all(
                color: Color.lerp(
                  colors.strokeDark,
                  _selectionStroke,
                  selection,
                )!,
                width: lerpDouble(3, 4.7878, selection)!,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            ),
            child: _SelectionShimmer(
              isSelected: isSelected,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: height),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.xl,
                    vertical: Spacing.md,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final allowance = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (MediaQuery.disableAnimationsOf(context))
                            allowanceText
                          else
                            ClipRect(
                              clipper: const _AllowanceClipper(),
                              clipBehavior: selection > 0 && selection < 1
                                  ? Clip.hardEdge
                                  : Clip.none,
                              child: AnimatedSize(
                                duration: Motion.slow,
                                curve: Curves.easeOutCubic,
                                alignment: AlignmentDirectional.centerStart,
                                clipBehavior: Clip.none,
                                child: SizedBox(
                                  width: double.infinity,
                                  child: AnimatedSwitcher(
                                    duration: Motion.slow,
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) {
                                      final size =
                                          child.key == const ValueKey(true)
                                          ? _selectedAllowanceSize
                                          : baseAllowanceSize;
                                      return FadeTransition(
                                        opacity: animation,
                                        child: Transform.scale(
                                          filterQuality: animation.isAnimating
                                              ? FilterQuality.medium
                                              : null,
                                          scale:
                                              visualAllowanceSize /
                                              textScaler.scale(size),
                                          alignment:
                                              AlignmentDirectional.centerStart,
                                          child: RepaintBoundary(child: child),
                                        ),
                                      );
                                    },
                                    layoutBuilder:
                                        (currentChild, previousChildren) {
                                          return Stack(
                                            alignment: AlignmentDirectional
                                                .centerStart,
                                            clipBehavior: Clip.none,
                                            children: [
                                              for (final child
                                                  in previousChildren)
                                                Positioned.fill(
                                                  child: OverflowBox(
                                                    minWidth: 0,
                                                    minHeight: 0,
                                                    maxHeight: double.infinity,
                                                    alignment:
                                                        AlignmentDirectional
                                                            .centerStart,
                                                    child: ExcludeSemantics(
                                                      child: child,
                                                    ),
                                                  ),
                                                ),
                                              ?currentChild,
                                            ],
                                          );
                                        },
                                    child: allowanceText,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: Spacing.xs),
                          includedAllowance,
                        ],
                      );
                      if (constraints.maxWidth < 260 ||
                          textScaler.scale(12) > 16) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            allowance,
                            const SizedBox(height: Spacing.sm),
                            Align(
                              alignment: Alignment.centerRight,
                              child: price,
                            ),
                          ],
                        );
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: allowance),
                          const SizedBox(width: Spacing.xs),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth / 2,
                            ),
                            child: price,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        if (hasBadge)
          Positioned(
            right: lerpDouble(-4, -9, selection),
            top: 0,
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 118,
                minHeight: 37.8867,
              ),
              padding: const EdgeInsets.fromLTRB(Spacing.md, 4, Spacing.md, 4),
              decoration: BoxDecoration(
                color: _badgeColor,
                border: Border.all(color: _outline, width: 3),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    left: -5,
                    top: -1,
                    child: Row(
                      children: [
                        _highlight(23),
                        const SizedBox(width: 2),
                        _highlight(6),
                      ],
                    ),
                  ),
                  Text(
                    badgeLabel!,
                    textAlign: TextAlign.center,
                    style: TextStyles.mini.copyWith(
                      color: _outline,
                      fontFamily: TextStyles.outfitFontFamily,
                      package: TextStyles.fontPackage,
                      fontWeight: FontWeight.w700,
                      height: 22 / 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _allowance(BuildContext context) {
    final colors = context.componentColors;
    final size = isSelected
        ? _selectedAllowanceSize
        : isFree
        ? 36.9512
        : 36.0;
    final unitSize = size * 4 / 9;
    final lineHeight = size * 7 / 9;
    return Text.rich(
      TextSpan(
        style: TextStyles.display1.copyWith(
          color: isSelected ? colors.specialWhite : colors.textBase,
          fontWeight: FontWeight.w700,
        ),
        children: [
          TextSpan(
            text: "$value ",
            style: TextStyle(
              fontSize: size,
              height: lineHeight / size,
              letterSpacing: -size * 0.05,
            ),
          ),
          TextSpan(
            text: unit,
            style: TextStyle(
              fontSize: unitSize,
              height: lineHeight / unitSize,
              letterSpacing: -unitSize * 0.05,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      key: ValueKey(isSelected),
      strutStyle: StrutStyle(
        fontFamily: TextStyles.outfitFontFamily,
        package: TextStyles.fontPackage,
        fontWeight: FontWeight.w700,
        fontSize: size,
        height: lineHeight.ceilToDouble() / size,
        forceStrutHeight: true,
      ),
    );
  }

  Widget _highlight(double width) => Container(
    width: width,
    height: 5,
    decoration: BoxDecoration(
      color: _badgeHighlight,
      borderRadius: BorderRadius.circular(2.5),
    ),
  );
}

class _AllowanceClipper extends CustomClipper<Rect> {
  const _AllowanceClipper();

  @override
  Rect getClip(Size size) => (Offset.zero & size).inflate(Spacing.xs);

  @override
  bool shouldReclip(_AllowanceClipper oldClipper) => false;
}

class _SelectionShimmer extends StatefulWidget {
  const _SelectionShimmer({required this.isSelected, required this.child});

  final bool isSelected;
  final Widget child;

  @override
  State<_SelectionShimmer> createState() => _SelectionShimmerState();
}

class _SelectionShimmerState extends State<_SelectionShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.slow * 2,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant _SelectionShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelected == widget.isSelected) return;
    if (widget.isSelected && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final white = context.componentColors.specialWhite;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final progress = const Interval(0.12, 1).transform(_controller.value);
        final sweep = progress * 4 - 2;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.button),
            gradient: progress > 0 && progress < 1
                ? LinearGradient(
                    begin: Alignment(sweep - 1, -1),
                    end: Alignment(sweep + 1, 1),
                    colors: [
                      white.withValues(alpha: 0),
                      white.withValues(
                        alpha: 0.40 * 4 * progress * (1 - progress),
                      ),
                      white.withValues(alpha: 0),
                    ],
                    stops: const [0.35, 0.5, 0.65],
                  )
                : null,
          ),
          child: child,
        );
      },
    );
  }
}

class SubscriptionPlanList extends StatelessWidget {
  const SubscriptionPlanList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: Spacing.lg),
          children[i],
        ],
      ],
    );
  }
}
