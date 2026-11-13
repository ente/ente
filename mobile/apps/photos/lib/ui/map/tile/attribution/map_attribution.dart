// ignore_for_file: invalid_use_of_internal_member

import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";

// Credit: This code is based on the Rich Attribution widget from the flutter_map
class MapAttributionWidget extends StatefulWidget {
  final List<SourceAttribution> attributions;

  final AttributionAlignment alignment;

  final Widget Function(BuildContext context, VoidCallback open)? openButton;

  final Widget Function(BuildContext context, VoidCallback close)? closeButton;

  final Color? popupBackgroundColor;

  final BorderRadius? popupBorderRadius;

  final double permanentHeight;

  final bool showFlutterMapAttribution;

  final RichAttributionWidgetAnimation animationConfig;

  final Duration popupInitialDisplayDuration;

  final double iconSize;
  const MapAttributionWidget({
    super.key,
    required this.attributions,
    this.alignment = AttributionAlignment.bottomRight,
    this.openButton,
    this.closeButton,
    this.popupBackgroundColor,
    this.popupBorderRadius,
    this.permanentHeight = 24,
    this.showFlutterMapAttribution = true,
    this.animationConfig = const FadeRAWA(),
    this.popupInitialDisplayDuration = Duration.zero,
    this.iconSize = 20,
  });

  @override
  State<StatefulWidget> createState() => MapAttributionWidgetState();
}

class MapAttributionWidgetState extends State<MapAttributionWidget> {
  StreamSubscription<MapEvent>? mapEventSubscription;

  final persistentAttributionKey = GlobalKey();
  Size? persistentAttributionSize;

  late bool popupExpanded = widget.popupInitialDisplayDuration != Duration.zero;
  bool persistentHovered = false;

  @override
  void initState() {
    super.initState();

    if (popupExpanded) {
      Future.delayed(
        widget.popupInitialDisplayDuration,
        () => setState(() => popupExpanded = false),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(
            () => persistentAttributionSize =
                (persistentAttributionKey.currentContext!.findRenderObject()
                        as RenderBox)
                    .size,
          );
        }
      }),
    );
  }

  @override
  void dispose() {
    mapEventSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final persistentAttributionItems = [
      ...List<Widget>.from(
        widget.attributions.whereType<LogoSourceAttribution>(),
        growable: false,
      ).interleave(SizedBox(width: widget.permanentHeight / 1.5)),
      if (widget.showFlutterMapAttribution)
        LogoSourceAttribution(
          Image.asset(
            'lib/assets/flutter_map_logo.png',
            package: 'flutter_map',
          ),
          tooltip: 'flutter_map',
          height: widget.permanentHeight,
        ),
      SizedBox(width: widget.permanentHeight * 0.1),
      AnimatedSwitcher(
        switchInCurve: widget.animationConfig.buttonCurve,
        switchOutCurve: widget.animationConfig.buttonCurve,
        duration: widget.animationConfig.buttonDuration,
        child: popupExpanded
            ? (widget.closeButton ??
                  (context, close) => IconButtonWidget(
                    size: widget.iconSize,
                    onTap: close,
                    icon: Icons.cancel_outlined,
                    iconButtonType: IconButtonType.primary,
                    iconColor: getEnteColorScheme(context).strokeBase,
                  ))(context, () => setState(() => popupExpanded = false))
            : (widget.openButton ??
                  (context, open) => IconButtonWidget(
                    size: widget.iconSize,
                    onTap: open,
                    icon: Icons.info_outlined,
                    iconButtonType: IconButtonType.primary,
                    iconColor: strokeBaseLight,
                  ))(context, () {
                setState(() => popupExpanded = true);
                mapEventSubscription = MapController().mapEventStream.listen((
                  e,
                ) {
                  setState(() => popupExpanded = false);
                  mapEventSubscription?.cancel();
                });
              }),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: widget.alignment.real,
        child: Stack(
          alignment: widget.alignment.real,
          children: [
            if (persistentAttributionSize != null)
              Padding(
                padding: const EdgeInsets.all(6),
                child: AnimatedScale(
                  scale: popupExpanded ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: popupExpanded ? Curves.easeOut : Curves.easeIn,
                  alignment: widget.alignment.real,
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          widget.popupBackgroundColor ??
                          Theme.of(context).colorScheme.surface,
                      border: Border.all(width: 0, style: BorderStyle.none),
                      borderRadius:
                          widget.popupBorderRadius ??
                          BorderRadius.only(
                            topLeft: const Radius.circular(10),
                            topRight: const Radius.circular(10),
                            bottomLeft:
                                widget.alignment ==
                                    AttributionAlignment.bottomLeft
                                ? Radius.zero
                                : const Radius.circular(10),
                            bottomRight:
                                widget.alignment ==
                                    AttributionAlignment.bottomRight
                                ? Radius.zero
                                : const Radius.circular(10),
                          ),
                    ),
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth < 420
                          ? constraints.maxWidth
                          : persistentAttributionSize!.width,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        height: widget.attributions.length * 32,
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...widget.attributions
                                .whereType<TextSourceAttribution>(),
                            SizedBox(
                              height: (widget.permanentHeight - 24) + 32,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            MouseRegion(
              key: persistentAttributionKey,
              onEnter: (_) => setState(() => persistentHovered = true),
              onExit: (_) => setState(() => persistentHovered = false),
              cursor: SystemMouseCursors.click,
              child: AnimatedOpacity(
                opacity: persistentHovered || popupExpanded ? 1 : 0.5,
                curve: widget.animationConfig.buttonCurve,
                duration: widget.animationConfig.buttonDuration,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: FittedBox(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children:
                          widget.alignment == AttributionAlignment.bottomLeft
                          ? persistentAttributionItems.reversed.toList()
                          : persistentAttributionItems,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
