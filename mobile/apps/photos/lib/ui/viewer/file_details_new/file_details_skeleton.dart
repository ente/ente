import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

enum FileDetailsSkeletonKind { people, menuRow }

class FileDetailsSectionSkeleton extends StatelessWidget {
  const FileDetailsSectionSkeleton({
    required this.kind,
    required this.height,
    super.key,
  });

  final FileDetailsSkeletonKind kind;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = context.componentColors.strokeFaint.withValues(alpha: 0.65);
    return SizedBox(
      height: height,
      child: switch (kind) {
        FileDetailsSkeletonKind.people => _people(color),
        FileDetailsSkeletonKind.menuRow => _menuRow(context, color),
      },
    );
  }

  Widget _people(Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _block(width: 88, height: 18, radius: 4, color: color),
      const SizedBox(height: Spacing.lg),
      Row(
        children: [
          for (var index = 0; index < 3; index++) ...[
            _block(width: 60, height: 60, radius: 18, color: color),
            if (index < 2) const SizedBox(width: Spacing.md),
          ],
        ],
      ),
    ],
  );

  Widget _menuRow(BuildContext context, Color color) =>
      Container(
        decoration: BoxDecoration(
          color: context.componentColors.fillLight,
          borderRadius: BorderRadius.circular(Radii.button),
        ),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        child: Row(
          children: [
            _block(width: 28, height: 28, radius: 8, color: color),
            const SizedBox(width: Spacing.md),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _block(width: 120, height: 12, radius: 3, color: color),
                const SizedBox(height: Spacing.sm),
                _block(width: 76, height: 8, radius: 3, color: color),
              ],
            ),
          ],
        ),
      );

  static Widget _block({
    required double width,
    required double height,
    required double radius,
    required Color color,
  }) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class FileDetailsInlineSkeleton extends StatelessWidget {
  const FileDetailsInlineSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 84,
    height: 9,
    decoration: BoxDecoration(
      color: context.componentColors.strokeFaint.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

class FileDetailsChipRowSkeleton extends StatelessWidget {
  const FileDetailsChipRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.componentColors.strokeFaint.withValues(alpha: 0.65);
    return Row(
      children: [
        _chip(width: 92, color: color),
        const SizedBox(width: Spacing.sm),
        _chip(width: 68, color: color),
      ],
    );
  }

  Widget _chip({required double width, required Color color}) => Container(
    width: width,
    height: 40,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
  );
}

class FileDetailsAnimatedSize extends StatelessWidget {
  const FileDetailsAnimatedSize({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    alignment: Alignment.topCenter,
    child: child,
  );
}
