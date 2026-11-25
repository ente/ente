import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/widgets/rewind_pixels.dart";
import "package:rive/rive.dart" as rive;

final _logger = Logger("RewindRive");

final _loadingRiveFiles = <Future<rive.File?>>{};

Future<void> rewindRiveFilesLoaded() => Future.wait(_loadingRiveFiles.toList());

Future<rive.File?> _loadRiveFile(String asset) {
  final file = _readRiveFile(asset);
  _loadingRiveFiles.add(file);
  return file.whenComplete(() => _loadingRiveFiles.remove(file));
}

void _fire(rive.ViewModelInstance? bindings, String name) {
  final trigger = bindings?.trigger(name);
  if (trigger == null) {
    _logger.warning("Trigger $name not found");
    return;
  }
  trigger.trigger();
  trigger.dispose();
}

Future<rive.File?> _readRiveFile(String asset) async {
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

RewindWarm<rive.File> rewindRiveWarm(String asset) =>
    RewindWarm(() => _loadRiveFile(asset), (file) => file.dispose());

class RewindDucky extends StatefulWidget {
  const RewindDucky(
    this.asset, {
    this.stateMachine = "Loop",
    this.play,
    this.active = true,
    this.warm,
    super.key,
  });

  final String asset;
  final String stateMachine;
  final String? play;
  final bool active;
  final RewindWarm<rive.File>? warm;

  @override
  State<RewindDucky> createState() => _RewindDuckyState();
}

class _RewindDuckyState extends State<RewindDucky> {
  static const _settleSteps = 80;
  static const _settleStepSeconds = 0.05;

  late final _warm = widget.warm;
  rive.File? _ownedFile;
  rive.RiveWidgetController? _controller;
  rive.ViewModelInstance? _bindings;
  var _played = false;
  var _settled = false;

  @override
  void initState() {
    super.initState();
    _warm?.hold();
    final warmed = _warm?.loaded;
    if (warmed == null) {
      _load();
    } else {
      _start(warmed);
    }
  }

  Future<void> _load() async {
    final file = await (_warm?.value ?? _loadRiveFile(widget.asset));
    if (file == null) return;
    if (!mounted) {
      if (_warm == null) file.dispose();
      return;
    }
    if (!_start(file)) return;
    _playOnce();
    setState(() {});
  }

  bool _start(rive.File file) {
    final owned = _warm == null;
    rive.RiveWidgetController? controller;
    rive.ViewModelInstance? bindings;
    try {
      controller = rive.RiveWidgetController(
        file,
        stateMachineSelector: rive.StateMachineNamed(widget.stateMachine),
      );
      final background = controller.artboard.component("Background");
      background
        ?..scaleX = 0
        ..scaleY = 0;
      if (widget.play != null) {
        bindings = controller.dataBind(rive.DataBind.auto());
      }
      controller.advance(0);
    } catch (error, stackTrace) {
      _logger.warning("Failed to start ${widget.asset}", error, stackTrace);
      bindings?.dispose();
      controller?.dispose();
      if (owned) file.dispose();
      return false;
    }
    if (owned) _ownedFile = file;
    _controller = controller;
    _bindings = bindings;
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playOnce();
    _settleWhenStill();
  }

  @override
  void didUpdateWidget(RewindDucky oldWidget) {
    super.didUpdateWidget(oldWidget);
    _playOnce();
  }

  void _playOnce() {
    final play = widget.play;
    if (play == null || _controller == null || !widget.active || _played) {
      return;
    }
    _played = true;
    _fire(_bindings, play);
    _settleWhenStill();
  }

  void _settleWhenStill() {
    final controller = _controller;
    if (controller == null || !_played || _settled) return;
    if (!MediaQuery.disableAnimationsOf(context)) return;
    for (var i = 0; i < _settleSteps; i++) {
      controller.advance(_settleStepSeconds);
    }
    _settled = true;
  }

  @override
  void dispose() {
    _bindings?.dispose();
    _controller?.dispose();
    _ownedFile?.dispose();
    _warm?.drop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.expand();
    return TickerMode(
      enabled: !MediaQuery.disableAnimationsOf(context),
      child: rive.RiveWidget(
        key: ValueKey(_settled),
        controller: controller,
        fit: rive.Fit.contain,
      ),
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
      _fire(_badges, widget.badge);
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
      _fire(
        _badges,
        widget.badge == RewindBadge.defaultBadge ? "replay" : widget.badge,
      );
    } catch (error, stackTrace) {
      _logger.warning("Failed to start the badge", error, stackTrace);
    }
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
      onTap: () => _fire(_badges, "replay"),
      child: rive.RiveWidget(controller: controller, fit: rive.Fit.contain),
    );
  }
}
