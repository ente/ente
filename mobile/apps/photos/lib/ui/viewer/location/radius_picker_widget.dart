import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/states/location_state.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/utils/dialog_util.dart";

class CustomTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    const trackHeight = 2.0;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(0, 0, trackWidth, trackHeight);
  }
}

class RadiusPickerWidget extends StatefulWidget {
  ///This notifier can be listened from a parent widget to get the selected radius
  final ValueNotifier<double> selectedRadiusNotifier;

  const RadiusPickerWidget(this.selectedRadiusNotifier, {super.key});

  @override
  State<RadiusPickerWidget> createState() => _RadiusPickerWidgetState();
}

class _RadiusPickerWidgetState extends State<RadiusPickerWidget> {
  final _logger = Logger("RadiusPickerWidget");
  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    widget.selectedRadiusNotifier.value = InheritedLocationTagData.of(
      context,
    ).selectedRadius;
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final radiusValues = InheritedLocationTagData.of(context).radiusValues;
    final selectedRadius = widget.selectedRadiusNotifier.value;
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final roundedRadius = roundRadius(selectedRadius);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _customRadiusOnTap,
          child: Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: colorScheme.fillFaint,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              border: Border.all(
                color: colorScheme.strokeFainter,
                width: 1,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 6,
                  child: Center(
                    child: Text(
                      roundedRadius,
                      style: double.parse(roundedRadius) < 1000
                          ? textTheme.largeBold
                          : textTheme.bodyBold,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Text(
                    AppLocalizations.of(context).kiloMeterUnit,
                    style: textTheme.miniMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context).radius,
                  style: textTheme.body,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 16,
                  child: SliderTheme(
                    data: SliderThemeData(
                      overlayColor: Colors.transparent,
                      thumbColor: strokeSolidMutedLight,
                      activeTrackColor: strokeSolidMutedLight,
                      inactiveTrackColor: colorScheme.strokeFaint,
                      activeTickMarkColor: colorScheme.strokeMuted,
                      inactiveTickMarkColor: strokeSolidMutedLight,
                      trackShape: CustomTrackShape(),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                        pressedElevation: 0,
                        elevation: 0,
                      ),
                      tickMarkShape: const RoundSliderTickMarkShape(
                        tickMarkRadius: 1,
                      ),
                    ),
                    child: RepaintBoundary(
                      child: Slider(
                        value: radiusValues.indexOf(selectedRadius).toDouble(),
                        onChanged: (value) {
                          setState(() {
                            widget.selectedRadiusNotifier.value =
                                radiusValues[value.toInt()];
                          });
                        },
                        min: 0,
                        max: radiusValues.length - 1,
                        divisions: radiusValues.length - 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  //9.99 -> 10, 9.0 -> 9, 5.02 -> 5, 5.09 -> 5.1
  //12.3 -> 12, 121.65 -> 122, 999.9 -> 1000
  String roundRadius(double radius) {
    String result;
    final roundedRadius = (radius * 10).round() / 10;
    if (radius >= 10) {
      result = roundedRadius.toStringAsFixed(0);
    } else {
      if (roundedRadius == roundedRadius.truncate()) {
        result = roundedRadius.truncate().toString();
      } else {
        result = roundedRadius.toStringAsFixed(1);
      }
    }

    return result;
  }

  Future<void> _customRadiusOnTap() async {
    final result = await showTextInputDialog(
      context,
      title: AppLocalizations.of(context).setRadius,
      onSubmit: (customRadius) async {
        final radius = double.tryParse(customRadius);
        if (radius != null) {
          final locationTagState = InheritedLocationTagData.of(context);
          locationTagState.updateRadiusValues([radius]);
          if (mounted) {
            setState(() {
              widget.selectedRadiusNotifier.value = radius;
            });
          }
        } else {
          throw Exception("Radius is null");
        }
      },
      submitButtonLabel: AppLocalizations.of(context).setLabel,
      textInputFormatter: [NumberWithDecimalInputFormatter(maxValue: 10000)],
      textInputType: const TextInputType.numberWithOptions(decimal: true),
      message: AppLocalizations.of(context).distanceInKMUnit,
      alignMessage: Alignment.centerRight,
    );
    if (result is Exception) {
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: result);
      _logger.severe("Failed to create custom radius", result);
    }
  }
}

class NumberWithDecimalInputFormatter extends TextInputFormatter {
  final RegExp _pattern = RegExp(r'^(?:\d+(\.\d*)?)?$');
  final double maxValue;

  NumberWithDecimalInputFormatter({required this.maxValue});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Check if the new value matches the pattern
    if (_pattern.hasMatch(newValue.text)) {
      if (newValue.text.isEmpty) {
        return newValue;
      }
      final newValueAsDouble = double.tryParse(newValue.text);

      // Check if the new value is within the allowed range
      if (newValueAsDouble != null && newValueAsDouble <= maxValue) {
        return newValue;
      }
    }
    return oldValue;
  }
}
