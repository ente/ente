import 'dart:convert';

import 'package:ente_components/theme/colors.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

enum AvatarComponentSize {
  xs(
    dimension: 16,
    borderWidth: 1,
    iconSize: 12,
    textStyle: TextStyle(
      fontFamily: TextStyles.fontFamily,
      package: TextStyles.fontPackage,
      fontSize: 8,
      height: 15 / 8,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
  ),
  small(
    dimension: 20,
    borderWidth: 1,
    iconSize: 14,
    textStyle: TextStyle(
      fontFamily: TextStyles.fontFamily,
      package: TextStyles.fontPackage,
      fontSize: 10,
      height: 15 / 10,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
  ),
  defaultSize(
    dimension: 24,
    borderWidth: 1,
    iconSize: 16,
    textStyle: TextStyle(
      fontFamily: TextStyles.fontFamily,
      package: TextStyles.fontPackage,
      fontSize: 12,
      height: 15 / 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
  ),
  @Deprecated('Use AvatarComponentSize.defaultSize instead.')
  normal(
    dimension: 24,
    borderWidth: 1,
    iconSize: 16,
    textStyle: TextStyle(
      fontFamily: TextStyles.fontFamily,
      package: TextStyles.fontPackage,
      fontSize: 12,
      height: 15 / 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
  ),
  medium(
    dimension: 28,
    borderWidth: 1,
    iconSize: 18,
    textStyle: TextStyle(
      fontFamily: TextStyles.fontFamily,
      package: TextStyles.fontPackage,
      fontSize: 12,
      height: 15 / 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
  ),
  large(
    dimension: 32,
    borderWidth: 2,
    iconSize: 18,
    textStyle: TextStyle(
      fontFamily: TextStyles.fontFamily,
      package: TextStyles.fontPackage,
      fontSize: 12,
      height: 15 / 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    ),
  ),
  contactHuge(
    dimension: 56,
    borderWidth: 2,
    iconSize: 24,
    textStyle: TextStyles.h2,
  );

  const AvatarComponentSize({
    required this.dimension,
    required this.borderWidth,
    required this.iconSize,
    required this.textStyle,
  });

  final double dimension;
  final double borderWidth;
  final double iconSize;
  final TextStyle textStyle;
}

enum AvatarComponentColor {
  yellow,
  green,
  orange,
  pink,
  purple,
  blue,
  cyan,
  black,
}

const List<AvatarComponentColor> avatarComponentIdentityPalette = [
  AvatarComponentColor.yellow,
  AvatarComponentColor.green,
  AvatarComponentColor.orange,
  AvatarComponentColor.pink,
  AvatarComponentColor.purple,
  AvatarComponentColor.blue,
  AvatarComponentColor.cyan,
];

/// A stable FNV-1a seed for identity colors across processes and platforms.
int avatarSeedForIdentity(String identityKey) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(identityKey.trim().toLowerCase())) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

AvatarComponentColor avatarComponentColorForIdentity(String identityKey) {
  return avatarComponentIdentityPalette[avatarSeedForIdentity(identityKey) %
      avatarComponentIdentityPalette.length];
}

Color avatarComponentColorValue(
  BuildContext context,
  AvatarComponentColor color,
) {
  final colors = context.componentColors;
  return switch (color) {
    AvatarComponentColor.yellow => colors.caution,
    AvatarComponentColor.green => colors.primary,
    AvatarComponentColor.orange => colors.accentOrange,
    AvatarComponentColor.pink => colors.accentPink,
    AvatarComponentColor.purple => colors.purple,
    AvatarComponentColor.blue => colors.blue,
    AvatarComponentColor.cyan => avatarCyan,
    AvatarComponentColor.black => Colors.black,
  };
}

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=2482-6547&m=dev
/// Section: Labels and avatars / Avatar
/// Specs: 16px, 20px, 24px, 28px, 32px, and 56px circular avatars with image, color, and add-icon variants.
class AvatarComponent extends StatelessWidget {
  const AvatarComponent({
    super.key,
    this.initials = '',
    this.size = AvatarComponentSize.defaultSize,
    this.color = AvatarComponentColor.yellow,
    this.seed,
    this.semanticLabel,
  }) : image = null,
       icon = null;

  const AvatarComponent.image({
    super.key,
    required this.image,
    this.size = AvatarComponentSize.defaultSize,
    this.semanticLabel,
  }) : initials = '',
       color = AvatarComponentColor.yellow,
       seed = null,
       icon = null;

  const AvatarComponent.icon({
    super.key,
    this.icon = const Icon(Icons.add_rounded),
    this.size = AvatarComponentSize.contactHuge,
    this.semanticLabel,
  }) : initials = '',
       image = null,
       color = AvatarComponentColor.yellow,
       seed = null;

  const AvatarComponent.seeded({
    super.key,
    required this.initials,
    required this.seed,
    this.size = AvatarComponentSize.defaultSize,
    this.semanticLabel,
  }) : image = null,
       color = AvatarComponentColor.yellow,
       icon = null;

  final String initials;
  final AvatarComponentSize size;
  final AvatarComponentColor color;
  final int? seed;
  final ImageProvider? image;
  final Widget? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final dimension = size.dimension;
    final borderWidth = size.borderWidth;
    final child = _child(context);

    return Semantics(
      image: image != null,
      label: semanticLabel ?? _semanticLabel,
      child: SizedBox.square(
        key: const ValueKey('avatar-surface'),
        dimension: dimension,
        child: image != null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.backgroundBase,
                    width: borderWidth,
                  ),
                  image: DecorationImage(image: image!, fit: BoxFit.cover),
                ),
              )
            : icon != null
            ? CustomPaint(
                foregroundPainter: _DashedCircleBorderPainter(
                  color: colors.strokeFaint,
                  strokeWidth: borderWidth,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.specialWhite,
                    shape: BoxShape.circle,
                  ),
                  child: Center(child: child),
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: _backgroundColor(context),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.backgroundBase,
                    width: borderWidth,
                  ),
                ),
                child: Center(child: child),
              ),
      ),
    );
  }

  Widget _child(BuildContext context) {
    if (icon != null) {
      return Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: IconTheme.merge(
          data: IconThemeData(
            color: context.componentColors.textLight,
            size: size.iconSize,
          ),
          child: icon!,
        ),
      );
    }

    final text = initials.trim().isEmpty ? '?' : initials.trim().toUpperCase();
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        textAlign: TextAlign.center,
        style: size.textStyle.copyWith(
          color: context.componentColors.specialWhite,
        ),
      ),
    );
  }

  Color _backgroundColor(BuildContext context) {
    if (seed != null) {
      final palette = Theme.of(context).brightness == Brightness.dark
          ? avatarDark
          : avatarLight;
      return palette[seed!.abs() % palette.length];
    }
    return avatarComponentColorValue(context, color);
  }

  String? get _semanticLabel {
    if (image != null) return 'AvatarComponent image';
    if (icon != null) return 'Add avatar';
    if (initials.trim().isEmpty) return 'AvatarComponent';
    return 'AvatarComponent $initials';
  }
}

class _DashedCircleBorderPainter extends CustomPainter {
  const _DashedCircleBorderPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    const dashLength = 4.0;
    const gapLength = 4.0;
    final circumference = 2 * 3.141592653589793 * radius;
    final dashCount = (circumference / (dashLength + gapLength)).floor();
    final sweep = (dashLength / circumference) * 2 * 3.141592653589793;
    final gap = (gapLength / circumference) * 2 * 3.141592653589793;

    for (var index = 0; index < dashCount; index++) {
      final start = index * (sweep + gap);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCircleBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
