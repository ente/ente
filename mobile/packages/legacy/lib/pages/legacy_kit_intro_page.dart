import "dart:math";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

const _pageMargin = 32.0;
const _cardRadius = 42.0;
const _cardContentLeft = 30.0;
const _sparkleSize = 22.0;
const _buttonHeight = 52.0;
const _settleCurve = Cubic(0, 0, 0, 1);

Future<bool> showLegacyKitIntroPage(BuildContext context) async {
  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (context) => const LegacyKitIntroPage()),
      ) ??
      false;
}

class LegacyKitIntroPage extends StatefulWidget {
  const LegacyKitIntroPage({super.key});

  @override
  State<LegacyKitIntroPage> createState() => _LegacyKitIntroPageState();
}

class _LegacyKitIntroPageState extends State<LegacyKitIntroPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );
  late final Animation<double> _header = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.3225, curve: Curves.easeOut),
  );
  late final Animation<double> _card1 = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.3653, curve: _settleCurve),
  );
  late final Animation<double> _card2 = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.58995, curve: _settleCurve),
  );
  late final Animation<double> _card3 = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.84936, curve: _settleCurve),
  );
  late final Animation<double> _button = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.46388, 0.89721, curve: Cubic(0, 0, 0.052, 1)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            final w = constraints.maxWidth;
            double y(double designPx) => designPx * h / 812;
            final contentWidth = min(w, 480.0);
            final contentLeft = (w - contentWidth) / 2;
            final textLeft = contentLeft + _pageMargin;
            final textWidth = contentWidth - 2 * _pageMargin;
            final card1Top = y(224);
            final card2Top = y(340);
            final card3Top = y(476);
            final buttonTop =
                h -
                max(y(48), MediaQuery.paddingOf(context).bottom + Spacing.sm) -
                _buttonHeight;
            final pad = y(8);
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [colors.specialWhite, colors.primary],
                          stops: const [0.04741, 0.95567],
                        ),
                      ),
                    ),
                    Positioned(
                      top: y(107),
                      left: 0,
                      right: 0,
                      height: y(770),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x008CBAFF), Color(0x9EFFFFFF)],
                            stops: [0.12143, 0.57208],
                          ),
                        ),
                      ),
                    ),
                    _card(
                      colors: colors,
                      maxHeight: h,
                      contentLeft: contentLeft,
                      contentWidth: contentWidth,
                      top: card1Top,
                      travel: y(584) * (1 - _card1.value),
                      stops: const [0.512, 1.0],
                      textTop: y(40),
                      textBoxHeight: card2Top - card1Top - y(40) - pad,
                      textDesignWidth: 231,
                      text: context.strings.legacyIntroCard1,
                    ),
                    _card(
                      colors: colors,
                      maxHeight: h,
                      contentLeft: contentLeft,
                      contentWidth: contentWidth,
                      top: card2Top,
                      travel: y(468) * (1 - _card2.value),
                      stops: const [0.512, 0.708],
                      textTop: y(37),
                      textBoxHeight: card3Top - card2Top - y(37) - pad,
                      textDesignWidth: 260,
                      text: context.strings.legacyIntroCard2,
                    ),
                    _card(
                      colors: colors,
                      maxHeight: h,
                      contentLeft: contentLeft,
                      contentWidth: contentWidth,
                      top: card3Top,
                      travel: y(374) * (1 - _card3.value),
                      stops: const [0.231, 1.0],
                      textTop: y(59),
                      textBoxHeight: max(0, buttonTop - card3Top - y(59) - pad),
                      textDesignWidth: 291,
                      text: context.strings.legacyIntroCard3,
                    ),
                    Positioned(
                      left: textLeft,
                      width: textWidth,
                      top: buttonTop,
                      height: _buttonHeight,
                      child: Transform.translate(
                        offset: Offset(0, y(143) * (1 - _button.value)),
                        child: Material(
                          color: colors.specialWhite,
                          borderRadius: Radii.buttonBorder,
                          child: InkWell(
                            borderRadius: Radii.buttonBorder,
                            onTap: () => Navigator.pop(context, true),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Spacing.xxl,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    context.strings.continueLabel,
                                    style: TextStyles.body.copyWith(
                                      color: colors.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: textLeft,
                      top: y(140),
                      child: Transform.translate(
                        offset: Offset(0, y(127) * (1 - _header.value)),
                        child: SizedBox(
                          width: textWidth,
                          height: card1Top - y(140) - pad,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: 311,
                              child: Text(
                                context.strings.legacyIntroTitle,
                                style: TextStyles.display3.copyWith(
                                  color: const Color(0xFF0A4AA7),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      child: SafeArea(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.pop(context, false),
                          child: const Padding(
                            padding: EdgeInsets.all(Spacing.lg),
                            child: Icon(
                              Icons.arrow_back_outlined,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _card({
    required ColorTokens colors,
    required double maxHeight,
    required double contentLeft,
    required double contentWidth,
    required double top,
    required double travel,
    required List<double> stops,
    required double textTop,
    required double textBoxHeight,
    required double textDesignWidth,
    required String text,
  }) {
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      height: maxHeight - top + _cardRadius,
      child: Transform.translate(
        offset: Offset(0, travel),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_cardRadius),
            border: Border.all(color: colors.specialWhite, width: 0.3),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [const Color(0xFF0A4499), colors.primary],
              stops: stops,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: contentLeft + _cardContentLeft,
                top: textTop,
                child: SizedBox(
                  width: contentWidth - _cardContentLeft - Spacing.xxl,
                  height: textBoxHeight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: _sparkleSize + Spacing.lg + textDesignWidth,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(
                              top: (28 - _sparkleSize) / 2,
                            ),
                            child: CustomPaint(
                              size: Size(_sparkleSize, _sparkleSize),
                              painter: _SparklePainter(),
                            ),
                          ),
                          const SizedBox(width: Spacing.lg),
                          Expanded(
                            child: Text(
                              text,
                              style: const TextStyle(
                                fontFamily: TextStyles.fontFamily,
                                package: TextStyles.fontPackage,
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                height: 28 / 24,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _SparklePainter extends CustomPainter {
  const _SparklePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width / sqrt2;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(pi / 4);
    final o = -side / 2;
    final path = Path()
      ..moveTo(o, o)
      ..quadraticBezierTo(o + side / 2, o + side * 0.45, o + side, o)
      ..quadraticBezierTo(o + side * 0.55, o + side / 2, o + side, o + side)
      ..quadraticBezierTo(o + side / 2, o + side * 0.55, o, o + side)
      ..quadraticBezierTo(o + side * 0.45, o + side / 2, o, o)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFF4D93B));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
