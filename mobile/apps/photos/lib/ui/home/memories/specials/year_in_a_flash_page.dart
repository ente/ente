import "dart:async";
import "dart:math";
import "dart:ui" as ui;

import "package:ente_components/theme/text_styles.dart" as component;
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/memories_changed_event.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/special_memory.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/home/memories/memory_music_session.dart";
import "package:photos/ui/home/memories/specials/special_memory_chrome.dart";

class YearInAFlashPage extends StatefulWidget {
  final YearInAFlashMemory memory;
  final bool isActive;
  final VoidCallback? onNextMemory;
  final VoidCallback? onPreviousMemory;

  const YearInAFlashPage({
    required this.memory,
    required this.isActive,
    this.onNextMemory,
    this.onPreviousMemory,
    super.key,
  });

  @override
  State<YearInAFlashPage> createState() => _YearInAFlashPageState();
}

class _YearInAFlashPageState extends State<YearInAFlashPage>
    with WidgetsBindingObserver {
  static const _pace = Duration(milliseconds: 250);
  static const _openingPaces = [620, 520, 430, 350, 290];
  static const _closingPaces = [330, 420, 560, 900];
  static const _bufferedAhead = 10;
  static const _keptBehind = 7;
  static const _startBuffer = 6;
  static const _finaleDuration = Duration(milliseconds: 4200);

  final Map<int, ui.Image> _prints = {};
  final Set<int> _unavailable = {};
  bool _isLoading = false;
  int _shown = -1;
  bool _isHeld = false;
  bool _isFinished = false;
  bool _isRouteCurrent = true;
  bool _isAppResumed = true;
  MemoryAudioScope? _memoryAudio;
  Timer? _timer;
  late final StreamSubscription<MemoriesChangedEvent> _memoriesChanged;

  late final List<Memory> _frames = List.of(widget.memory.memories);
  final Set<Memory> _preloaded = {};

  bool get _isRunning =>
      widget.isActive && _isRouteCurrent && _isAppResumed && !_isHeld;

  bool get _hasFailed => _unavailable.length == _frames.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isAppResumed = _isResumed(WidgetsBinding.instance.lifecycleState);
    _memoriesChanged = Bus.instance.on<MemoriesChangedEvent>().listen((_) {
      if (!_dropRemovedFrames()) return;
      setState(() {});
      if (_isRunning) _schedule();
    });
    unawaited(_buffer());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _memoryAudio = MemoryAudioScope.maybeOf(context);
    _isRouteCurrent = ModalRoute.isCurrentOf(context) ?? true;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppResumed = _isResumed(state);
    _sync();
  }

  bool _isResumed(AppLifecycleState? state) {
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(covariant YearInAFlashPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    if (widget.isActive && _isFinished) _restart();
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _memoriesChanged.cancel();
    _timer?.cancel();
    for (final print in _prints.values) {
      print.dispose();
    }
    super.dispose();
  }

  void _sync() {
    if (widget.isActive) {
      _memoryAudio?.activateMusic(
        widget.memory.id,
        currentItemIsVideo: false,
        viewerActionPaused: !_isRouteCurrent,
      );
    }
    if (!_isRunning) {
      _timer?.cancel();
    } else if (!(_timer?.isActive ?? false)) {
      _schedule();
    }
  }

  void _restart() {
    _timer?.cancel();
    for (final print in _prints.values) {
      print.dispose();
    }
    setState(() {
      _shown = -1;
      _isFinished = false;
      _prints.clear();
      _unavailable.clear();
    });
    unawaited(_buffer());
    _sync();
  }

  int? get _nextToLoad {
    var printsAhead = 0;
    for (var frame = _shown + 1; frame < _frames.length; frame++) {
      if (_prints.containsKey(frame)) {
        if (++printsAhead == _bufferedAhead) return null;
      } else if (!_unavailable.contains(frame)) {
        return frame;
      }
    }
    return null;
  }

  int? get _nextPrint {
    var next = _shown + 1;
    while (next < _frames.length && _unavailable.contains(next)) {
      next++;
    }
    final isStillLoading = next < _frames.length && !_prints.containsKey(next);
    return isStillLoading ? null : next;
  }

  bool get _canStart {
    final loadable = _frames.length - _unavailable.length;
    return _prints.length >= min(_startBuffer, loadable);
  }

  Future<void> _buffer() async {
    if (_isLoading) return;
    _isLoading = true;
    try {
      while (mounted) {
        _dropRemovedFrames();
        final frame = _nextToLoad;
        if (frame == null) return;
        _preloadFrom(frame);
        final print = await _decode(_frames[frame]);
        if (!mounted) {
          print?.dispose();
          return;
        }
        if (print == null) {
          _unavailable.add(frame);
        } else {
          _prints[frame] = print;
        }
        if (_shown < 0) setState(() {});
        if (_isRunning && !(_timer?.isActive ?? false)) _schedule();
      }
    } finally {
      _isLoading = false;
    }
  }

  void _preloadFrom(int frame) {
    final window = _frames.skip(frame).take(_bufferedAhead);
    for (final ahead in window) {
      if (ahead.file.isRemoteOnlyFile && _preloaded.add(ahead)) {
        preloadThumbnail(ahead.file);
      }
    }
  }

  Future<ui.Image?> _decode(Memory frame) async {
    try {
      final bytes = await getThumbnail(frame.file);
      if (bytes == null) return null;
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  bool _dropRemovedFrames() {
    final remaining = widget.memory.memories;
    if (remaining.length == _frames.length) return false;
    var hasDropped = false;
    for (final (index, frame) in _frames.indexed) {
      if (remaining.contains(frame)) continue;
      _prints.remove(index)?.dispose();
      hasDropped = _unavailable.add(index) || hasDropped;
    }
    return hasDropped;
  }

  Duration _paceOf(int frame) {
    if (frame < _openingPaces.length) {
      return Duration(milliseconds: _openingPaces[frame]);
    }
    final fromEnd = _frames.length - 1 - frame;
    if (fromEnd < _closingPaces.length) {
      return Duration(
        milliseconds: _closingPaces[_closingPaces.length - 1 - fromEnd],
      );
    }
    return _pace;
  }

  void _schedule() {
    _timer?.cancel();
    if (_isFinished) {
      _timer = Timer(_finaleDuration, () => widget.onNextMemory?.call());
      return;
    }
    _dropRemovedFrames();
    final next = _nextPrint;
    if (next == null || _hasFailed) return;
    if (_shown < 0) {
      if (_canStart) _timer = Timer(Duration.zero, () => _deal(next));
      return;
    }
    _timer = Timer(
      _paceOf(_shown),
      next < _frames.length ? () => _deal(next) : _finish,
    );
  }

  void _deal(int next) {
    final turnsTheMonth =
        _shown < 0 ||
        wallClockOf(_frames[_shown].file).month !=
            wallClockOf(_frames[next].file).month;
    if (turnsTheMonth) tickHaptic();
    setState(() => _shown = next);
    _dropOldPrints();
    unawaited(_buffer());
    _schedule();
  }

  void _dropOldPrints() {
    _prints.removeWhere((frame, print) {
      final isOld = frame < _shown - _keptBehind;
      if (isOld) print.dispose();
      return isOld;
    });
  }

  void _finish() {
    setState(() => _isFinished = true);
    unawaited(_markSeen());
    _schedule();
  }

  Future<void> _markSeen() async {
    final unseen = widget.memory.memories
        .where((frame) => !frame.isSeen())
        .toList();
    for (final frame in unseen) {
      await memoriesCacheService.markMemoryAsSeen(frame, frame == unseen.last);
    }
  }

  void _hold(bool isHeld) {
    _isHeld = isHeld;
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    final safePadding = MediaQuery.paddingOf(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final shown = _shown < 0 ? null : _frames[_shown];
    final taken = shown == null ? null : wallClockOf(shown.file);
    final month = taken == null
        ? ""
        : DateFormat.MMMM(locale).format(taken).toUpperCase();
    return SpecialMemoryGestures(
      onHold: _hold,
      onPreviousMemory: widget.onPreviousMemory,
      onNextMemory: widget.onNextMemory,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _FlashBackdrop(),
          Positioned(
            left: 0,
            right: 0,
            top: safePadding.top + 136,
            child: Column(
              children: [
                Text(
                  "${memory.year}",
                  style: specialDisplayStyle(
                    20,
                    color: SpecialMemoryColors.yellow,
                  ).copyWith(letterSpacing: 4),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 50,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.35),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      month,
                      key: ValueKey(month),
                      style: specialDisplayStyle(44),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            top: safePadding.top + 238,
            bottom: safePadding.bottom + 150,
            child: _hasFailed
                ? SpecialMemoryLoadFailure(onRetry: _restart)
                : _shown < 0
                ? const Center(
                    child: SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ),
                  )
                : _Pile(prints: _prints, shown: _shown, depth: _keptBehind),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: safePadding.bottom + 84,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: _isFinished
                  ? _Finale(
                      key: const ValueKey("finale"),
                      year: memory.year,
                      onReplay: _restart,
                    )
                  : _MonthTrack(
                      key: const ValueKey("months"),
                      month: taken?.month ?? 0,
                    ),
            ),
          ),
          SpecialMemoryHeader(
            memoryID: memory.id,
            title: memory.title,
            subtitle: taken == null
                ? null
                : DateFormat.MMMMd(locale).format(taken),
            progress: _FlashProgress(
              value: _frames.isEmpty ? 0 : (_shown + 1) / _frames.length,
            ),
          ),
          const SpecialMemoryMuteButton(),
        ],
      ),
    );
  }
}

class _FlashBackdrop extends StatelessWidget {
  const _FlashBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.1),
          radius: 1.1,
          colors: [Color(0xFF2A2A30), Color(0xFF0C0C0E)],
        ),
      ),
    );
  }
}

class _FlashProgress extends StatelessWidget {
  final double value;

  const _FlashProgress({required this.value});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 220),
      builder: (context, value, _) => LinearProgressIndicator(
        value: value,
        minHeight: 4,
        backgroundColor: Colors.white.withValues(alpha: 0.4),
        valueColor: const AlwaysStoppedAnimation(Colors.white),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class _Pile extends StatelessWidget {
  final Map<int, ui.Image> prints;
  final int shown;
  final int depth;

  const _Pile({required this.prints, required this.shown, required this.depth});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Size(
          constraints.maxWidth * 0.8,
          constraints.maxHeight * 0.9,
        );
        return Stack(
          alignment: Alignment.center,
          children: [
            for (var frame = max(0, shown - depth); frame <= shown; frame++)
              if (prints[frame] case final print?)
                _Print(
                  key: ValueKey(frame),
                  image: print,
                  frame: frame,
                  bounds: bounds,
                  isTop: frame == shown,
                ),
          ],
        );
      },
    );
  }
}

class _Print extends StatelessWidget {
  static const _border = 7.0;

  final ui.Image image;
  final int frame;
  final Size bounds;
  final bool isTop;

  const _Print({
    required this.image,
    required this.frame,
    required this.bounds,
    required this.isTop,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final random = Random(frame * 7919);
    final angle = (random.nextDouble() - 0.5) * 0.2;
    final offset = Offset(
      (random.nextDouble() - 0.5) * 26,
      (random.nextDouble() - 0.5) * 22,
    );
    final aspectRatio = (image.width / image.height).clamp(0.7, 1.45);
    final width = min(bounds.width, bounds.height * aspectRatio);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      builder: (context, landed, child) => Transform.translate(
        offset: offset + Offset(0, -26 * (1 - landed)),
        child: Transform.rotate(
          angle: angle + 0.06 * (1 - landed),
          child: Transform.scale(
            scale: 1.14 - 0.14 * landed,
            child: Opacity(opacity: landed.clamp(0.0, 1.0), child: child),
          ),
        ),
      ),
      child: Container(
        width: width,
        height: width / aspectRatio,
        padding: const EdgeInsets.all(_border),
        decoration: BoxDecoration(
          color: SpecialMemoryColors.photoPaper,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          color: Colors.black.withValues(alpha: isTop ? 0 : 0.16),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: RawImage(image: image, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _MonthTrack extends StatelessWidget {
  final int month;

  const _MonthTrack({required this.month, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 1; index <= DateTime.monthsPerYear; index++) ...[
          if (index > 1) const SizedBox(width: 5),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: index == month ? 10 : 6,
              decoration: BoxDecoration(
                color: index == month
                    ? SpecialMemoryColors.yellow
                    : Colors.white.withValues(
                        alpha: index < month ? 0.9 : 0.25,
                      ),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Finale extends StatelessWidget {
  final int year;
  final VoidCallback onReplay;

  const _Finale({required this.year, required this.onReplay, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            context.strings.thatWasYear(year: year),
            style: specialDisplayStyle(26),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 14),
        GestureDetector(
          onTap: onReplay,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.replay_rounded,
                  size: 18,
                  color: SpecialMemoryColors.ink,
                ),
                const SizedBox(width: 6),
                Text(
                  context.strings.replay,
                  style: component.TextStyles.bodyBold.copyWith(
                    color: SpecialMemoryColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
