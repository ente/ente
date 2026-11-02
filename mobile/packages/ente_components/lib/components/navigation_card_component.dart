import 'dart:async';

import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class NavigationCardComponent extends StatefulWidget {
  const NavigationCardComponent({
    super.key,
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.onTap,
  });

  static const double leadingSize = 34;

  final String title;
  final String subtitle;
  final Widget leading;
  final FutureOr<void> Function() onTap;

  @override
  State<NavigationCardComponent> createState() =>
      _NavigationCardComponentState();
}

class _NavigationCardComponentState extends State<NavigationCardComponent> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: !_isBusy,
        child: Material(
          color: colors.fillLight,
          borderRadius: Radii.buttonBorder,
          child: InkWell(
            onTap: _isBusy ? null : _onTap,
            borderRadius: Radii.buttonBorder,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 80),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.xxl,
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: SizedBox.square(
                        dimension: NavigationCardComponent.leadingSize,
                        child: widget.leading,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyles.bodyBold.copyWith(
                              color: colors.textBase,
                              fontSize: 15,
                              height: 20 / 15,
                            ),
                          ),
                          Text(
                            widget.subtitle,
                            style: TextStyles.mini.copyWith(
                              color: colors.textLight,
                              height: 18 / 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    ExcludeSemantics(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.fillDark,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(
                          dimension: 32,
                          child: Center(
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowRight01,
                              size: IconSizes.small,
                              color: colors.textBase,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onTap() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await widget.onTap();
    } catch (_) {
      return;
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}
