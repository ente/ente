import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:rive/rive.dart" as rive;

final _logger = Logger("RewindRive");

Future<rive.File?> _loadRiveFile(String asset) async {
  try {
    return await rive.File.path(
      RewindAssets.file(asset).path,
      riveFactory: rive.Factory.flutter,
    );
  } catch (error, stackTrace) {
    _logger.warning("Failed to load $asset", error, stackTrace);
    return null;
  }
}

class RewindDucky extends StatefulWidget {
  const RewindDucky(this.asset, {super.key});

  final String asset;

  @override
  State<RewindDucky> createState() => _RewindDuckyState();
}

class _RewindDuckyState extends State<RewindDucky> {
  rive.File? _file;
  rive.RiveWidgetController? _controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final file = await _loadRiveFile(widget.asset);
    if (file == null) return;
    if (!mounted) {
      file.dispose();
      return;
    }
    try {
      final controller = rive.RiveWidgetController(
        file,
        stateMachineSelector: const rive.StateMachineNamed("Loop"),
      );
      final background = controller.artboard.component("Background");
      background
        ?..scaleX = 0
        ..scaleY = 0;
      controller.advance(0);
      setState(() {
        _file = file;
        _controller = controller;
      });
    } catch (error, stackTrace) {
      _logger.warning("Failed to start ${widget.asset}", error, stackTrace);
      file.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.expand();
    return TickerMode(
      enabled: !MediaQuery.disableAnimationsOf(context),
      child: rive.RiveWidget(controller: controller, fit: rive.Fit.contain),
    );
  }
}

class RewindBadge extends StatefulWidget {
  const RewindBadge({required this.badge, required this.active, super.key});

  static const defaultBadge = "sun_chaser";
  static const ids = [
    "sun_chaser",
    "consistency_champ",
    "unpaid_photographer",
    "main_character",
    "early_bird",
    "night_owl",
    "weekend_star",
    "pawparazzi",
    "foodie",
    "plant_parent",
    "building_buff",
    "screenshot_collector",
    "hobby_hopper",
    "indoor_kid",
    "out_of_office",
    "full_throttle",
    "event_hopper",
    "always_rolling",
    "fit_check",
    "art_lover",
    "limited_edition",
    "happy_snapper",
    "opening_credits",
    "guest_star",
    "mixed_bag",
  ];

  final String badge;
  final bool active;

  @override
  State<RewindBadge> createState() => _RewindBadgeState();
}

class _RewindBadgeState extends State<RewindBadge> {
  rive.File? _file;
  rive.RiveWidgetController? _controller;
  rive.ViewModelInstance? _badges;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final file = await _loadRiveFile(RewindAssets.badges);
    if (file == null) return;
    if (!mounted) {
      file.dispose();
      return;
    }
    _file = file;
    _reveal();
  }

  @override
  void didUpdateWidget(RewindBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller == null) {
      _reveal();
    } else if (widget.badge != oldWidget.badge) {
      _fire(widget.badge);
    }
  }

  void _reveal() {
    final file = _file;
    if (file == null || !widget.active || _controller != null) return;
    try {
      final controller = rive.RiveWidgetController(
        file,
        stateMachineSelector: const rive.StateMachineNamed("Badge"),
      );
      _badges = controller.dataBind(rive.DataBind.auto());
      controller.advance(0);
      setState(() => _controller = controller);
      _fire(widget.badge == RewindBadge.defaultBadge ? "replay" : widget.badge);
    } catch (error, stackTrace) {
      _logger.warning("Failed to start the badge", error, stackTrace);
    }
  }

  void _fire(String name) {
    final trigger = _badges?.trigger(name);
    if (trigger == null) {
      _logger.warning("Badge trigger $name not found");
      return;
    }
    trigger.trigger();
    trigger.dispose();
  }

  @override
  void dispose() {
    _badges?.dispose();
    _controller?.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.expand();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _fire("replay"),
      child: rive.RiveWidget(controller: controller, fit: rive.Fit.contain),
    );
  }
}
