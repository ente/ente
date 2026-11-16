import "dart:async";
import "dart:math";

import "package:ente_components/theme/text_styles.dart" as component;
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/memories_changed_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/special_memory.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/home/memories/memory_music_session.dart";
import "package:photos/ui/home/memories/memory_progress_indicator.dart";
import "package:photos/ui/home/memories/specials/special_memory_chrome.dart";
import "package:photos/ui/viewer/gallery/jump_to_date_gallery.dart";

class ThenAndNowPage extends StatefulWidget {
  final ThenAndNowMemory memory;
  final bool isActive;
  final VoidCallback? onNextMemory;
  final VoidCallback? onPreviousMemory;

  const ThenAndNowPage({
    required this.memory,
    required this.isActive,
    this.onNextMemory,
    this.onPreviousMemory,
    super.key,
  });

  @override
  State<ThenAndNowPage> createState() => _ThenAndNowPageState();
}

class _ThenAndNowPageState extends State<ThenAndNowPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _showDuration = Duration(seconds: 11);
  static const _fallbackAspectRatio = 3 / 4;
  static const _tallestAspectRatio = 0.68;
  static const _widestAspectRatio = 1.5;

  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  );
  late final _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _revealedSplit = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(1), weight: 10),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 0,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 15,
    ),
    TweenSequenceItem(tween: ConstantTween(0), weight: 6),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0,
        end: 0.5,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 7,
    ),
  ]).animate(_reveal);
  final _split = ValueNotifier<double>(1);
  Animation<double>? _snappedSplit;
  AnimationController? _progress;
  Size? _nowSize;
  bool _isThenReady = false;
  bool _hasFailed = false;
  int _attempt = 0;
  bool _hasStarted = false;
  bool _hasRevealed = false;
  bool _hasCompared = false;
  bool _isHeld = false;
  bool _isRouteCurrent = true;
  bool _isAppResumed = true;
  MemoryAudioScope? _memoryAudio;
  late final StreamSubscription<MemoriesChangedEvent> _memoriesChanged;

  late final Memory _then = widget.memory.then;
  late final Memory _now = widget.memory.now;

  bool get _isReady => _nowSize != null && _isThenReady;

  bool get _isPlaying =>
      widget.isActive &&
      _isRouteCurrent &&
      _isAppResumed &&
      _isReady &&
      !_isHeld;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isAppResumed = _isResumed(WidgetsBinding.instance.lifecycleState);
    _reveal.addListener(() => _split.value = _revealedSplit.value);
    _reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _hasRevealed = true);
      }
    });
    _snap.addListener(() {
      final snappedSplit = _snappedSplit;
      if (snappedSplit != null) _split.value = snappedSplit.value;
    });
    _memoriesChanged = Bus.instance.on<MemoriesChangedEvent>().listen((_) {
      if (!widget.memory.isShowable) setState(() {});
    });
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
  void didUpdateWidget(covariant ThenAndNowPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    if (widget.isActive) {
      _hasStarted = false;
      _hasRevealed = false;
      _hasCompared = false;
      _split.value = 1;
      _reveal.reset();
      _progress?.reset();
    }
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _memoriesChanged.cancel();
    _reveal.dispose();
    _snap.dispose();
    _split.dispose();
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
    if (!_isPlaying) {
      _reveal.stop();
      _progress?.stop();
      return;
    }
    if (!_hasStarted) {
      _hasStarted = true;
      unawaited(memoriesCacheService.markMemoryAsSeen(_then, false));
      unawaited(memoriesCacheService.markMemoryAsSeen(_now, true));
    }
    if (!_hasCompared && !_reveal.isCompleted) _reveal.forward();
    _progress?.forward();
  }

  void _onNowReady(Size size) {
    setState(() => _nowSize = size);
    _sync();
  }

  void _onThenReady(Size _) {
    setState(() => _isThenReady = true);
    _sync();
  }

  void _onFailed() {
    setState(() => _hasFailed = true);
  }

  void _retry() {
    setState(() {
      _hasFailed = false;
      _nowSize = null;
      _isThenReady = false;
      _attempt++;
    });
  }

  void _hold(bool isHeld) {
    _isHeld = isHeld;
    _sync();
  }

  void _dragTo(double split) {
    _reveal.stop();
    _snap.stop();
    if (!_hasCompared) setState(() => _hasCompared = true);
    final clamped = split.clamp(0.0, 1.0);
    if ((clamped - 0.5) * (_split.value - 0.5) < 0) tickHaptic();
    _split.value = clamped;
  }

  void _snapTo(double split) {
    _reveal.stop();
    if (!_hasCompared) setState(() => _hasCompared = true);
    _snappedSplit = Tween<double>(
      begin: _split.value,
      end: split.clamp(0.0, 1.0),
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_snap);
    _snap.forward(from: 0);
  }

  double get _aspectRatio {
    final size = _nowSize;
    final aspectRatio = size == null || size.isEmpty
        ? _fallbackAspectRatio
        : size.width / size.height;
    return aspectRatio.clamp(_tallestAspectRatio, _widestAspectRatio);
  }

  Future<void> _openDate(EnteFile file) async {
    _hold(true);
    await routeToPage(context, JumpToDateGallery(fileToJumpTo: file));
    if (!mounted) return;
    if (widget.memory.isShowable) {
      _hold(false);
      return;
    }
    final onOtherMemory = widget.onNextMemory ?? widget.onPreviousMemory;
    if (onOtherMemory != null) {
      onOtherMemory();
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    final safePadding = MediaQuery.paddingOf(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    String dateOf(EnteFile file) =>
        DateFormat.yMMMd(locale).format(wallClockOf(file));
    return SpecialMemoryGestures(
      onHold: _hold,
      onPreviousMemory: widget.onPreviousMemory,
      onNextMemory: widget.onNextMemory,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (memory.isShowable)
            Stack(
              fit: StackFit.expand,
              children: [
                SpecialMemoryBackdrop(_now.file, key: ValueKey(_attempt)),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    safePadding.top + 132,
                    16,
                    safePadding.bottom + 88,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        context.strings.yearsApart(count: memory.yearsApart),
                        style: specialDisplayStyle(36),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Flexible(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          child: AspectRatio(
                            aspectRatio: _aspectRatio,
                            child: _hasFailed
                                ? SpecialMemoryLoadFailure(onRetry: _retry)
                                : AnimatedOpacity(
                                    opacity: _isReady ? 1 : 0,
                                    duration: const Duration(milliseconds: 350),
                                    child: _CompareFrame(
                                      split: _split,
                                      then: MemoryPhoto(
                                        _then.file,
                                        key: ValueKey("then-$_attempt"),
                                        loadsOriginal: true,
                                        onReady: _onThenReady,
                                        onFailed: _onFailed,
                                      ),
                                      now: MemoryPhoto(
                                        _now.file,
                                        key: ValueKey("now-$_attempt"),
                                        loadsOriginal: true,
                                        onReady: _onNowReady,
                                        onFailed: _onFailed,
                                      ),
                                      thenYear: memory.thenYear,
                                      nowYear: memory.nowYear,
                                      onDrag: _dragTo,
                                      onTap: _snapTo,
                                      invitesDrag:
                                          _hasRevealed && !_hasCompared,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _DateLink(
                            dateOf(_then.file),
                            onTap: () => _openDate(_then.file),
                          ),
                          const Spacer(),
                          _DateLink(
                            dateOf(_now.file),
                            onTap: () => _openDate(_now.file),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AnimatedOpacity(
                        opacity: _hasCompared || _hasFailed ? 0 : 0.8,
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          context.strings.dragToCompare,
                          style: component.TextStyles.mini.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            const SizedBox.shrink(),
          SpecialMemoryHeader(
            memoryID: memory.id,
            title: memory.title,
            subtitle: "${memory.thenYear} – ${memory.nowYear}",
            progress: MemoryProgressIndicator(
              totalSteps: 1,
              currentIndex: 0,
              duration: _showDuration,
              unselectedColor: Colors.white.withValues(alpha: 0.4),
              animationController: (controller) {
                _progress = controller;
                if (_isPlaying) controller.forward();
              },
              onAnimationControllerDisposed: (controller) {
                if (_progress == controller) _progress = null;
              },
              onComplete: () => widget.onNextMemory?.call(),
            ),
          ),
          const SpecialMemoryMuteButton(),
        ],
      ),
    );
  }
}

class _CompareFrame extends StatelessWidget {
  static const _handleSize = 44.0;
  static const _edgeFade = 0.07;

  final ValueNotifier<double> split;
  final Widget then;
  final Widget now;
  final int thenYear;
  final int nowYear;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onTap;
  final bool invitesDrag;

  const _CompareFrame({
    required this.split,
    required this.then,
    required this.now,
    required this.thenYear,
    required this.nowYear,
    required this.onDrag,
    required this.onTap,
    required this.invitesDrag,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) =>
              onDrag(details.localPosition.dx / size.width),
          onHorizontalDragUpdate: (details) =>
              onDrag(details.localPosition.dx / size.width),
          onTapUp: (details) => onTap(details.localPosition.dx / size.width),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 32,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  now,
                  ValueListenableBuilder<double>(
                    valueListenable: split,
                    child: then,
                    builder: (context, value, child) =>
                        ClipRect(clipper: LeftPartClipper(value), child: child),
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: split,
                    builder: (context, value, _) {
                      final x = value * size.width;
                      final awayFromEdge = (min(value, 1 - value) / _edgeFade)
                          .clamp(0.0, 1.0);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            left: 12,
                            top: 12,
                            child: _YearChip(
                              thenYear,
                              opacity: ((value - 0.14) / 0.14).clamp(0.0, 1.0),
                            ),
                          ),
                          Positioned(
                            right: 12,
                            top: 12,
                            child: _YearChip(
                              nowYear,
                              opacity: ((0.86 - value) / 0.14).clamp(0.0, 1.0),
                            ),
                          ),
                          Positioned(
                            left: x - 1.5,
                            top: 0,
                            bottom: 0,
                            width: 3,
                            child: Opacity(
                              opacity: awayFromEdge,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x59000000),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: x - _handleSize / 2,
                            top: (size.height - _handleSize) / 2,
                            child: Opacity(
                              opacity: awayFromEdge,
                              child: _Handle(
                                _handleSize,
                                invitesDrag: invitesDrag,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Handle extends StatefulWidget {
  final double size;
  final bool invitesDrag;

  const _Handle(this.size, {required this.invitesDrag});

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Handle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invitesDrag != widget.invitesDrag) _sync();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _sync() {
    if (widget.invitesDrag) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.animateTo(0, duration: const Duration(milliseconds: 150));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(
        begin: 1,
        end: 1.16,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chevron_left_rounded,
              size: 20,
              color: SpecialMemoryColors.ink,
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: SpecialMemoryColors.ink,
            ),
          ],
        ),
      ),
    );
  }
}

class _YearChip extends StatelessWidget {
  final int year;
  final double opacity;

  const _YearChip(this.year, {required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x8C000000),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          "$year",
          style: specialDisplayStyle(16).copyWith(height: 1.2),
        ),
      ),
    );
  }
}

class _DateLink extends StatelessWidget {
  final String date;
  final VoidCallback onTap;

  const _DateLink(this.date, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              date,
              style: component.TextStyles.mini.copyWith(color: Colors.white),
            ),
            const Icon(Icons.chevron_right, size: 14, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
