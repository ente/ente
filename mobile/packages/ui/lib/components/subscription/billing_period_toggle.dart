import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

class BillingPeriodToggle extends StatefulWidget {
  final String monthlyLabel;
  final String yearlyLabel;
  final bool isYearly;
  final ValueChanged<bool> onToggle;
  const BillingPeriodToggle({
    required this.monthlyLabel,
    required this.yearlyLabel,
    required this.isYearly,
    required this.onToggle,
    super.key,
  });

  @override
  State<BillingPeriodToggle> createState() => _BillingPeriodToggleState();
}

class _BillingPeriodToggleState extends State<BillingPeriodToggle> {
  static const double _padding = Spacing.xs;
  static const double _minSegmentHeight = 41;
  static const double _radius = 35;

  late bool _isYearly;

  @override
  void initState() {
    super.initState();
    _isYearly = widget.isYearly;
  }

  @override
  void didUpdateWidget(covariant BillingPeriodToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isYearly != widget.isYearly) {
      _isYearly = widget.isYearly;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final labelStyle = TextStyles.body.copyWith(color: colors.textBase);
    return Container(
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: colors.fillDark,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: Motion.slow,
              curve: Curves.easeInOutCubic,
              alignment: _isYearly
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.fillLight,
                    borderRadius: BorderRadius.circular(_radius),
                  ),
                ),
              ),
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _segment(widget.monthlyLabel, false, labelStyle),
                _segment(widget.yearlyLabel, true, labelStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(String label, bool isYearly, TextStyle style) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setIsYearly(isYearly),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minSegmentHeight),
          child: Center(
            child: Text(label, style: style, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  void setIsYearly(bool isYearly) {
    if (_isYearly == isYearly) return;
    setState(() {
      _isYearly = isYearly;
    });
    widget.onToggle(isYearly);
  }
}
