import "dart:async";
import "dart:math";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:photos/ui/rewind/shell/rewind_chrome.dart";
import "package:photos/ui/rewind/shell/rewind_music.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/utils/share_util.dart";

class RewindViewer extends StatefulWidget {
  const RewindViewer({
    required this.pages,
    this.initialPage,
    this.initialStop = 0,
    this.onSettled,
    super.key,
  });

  final List<RewindPage> pages;
  final String? initialPage;
  final int initialStop;
  final void Function(RewindPage page, int stop)? onSettled;

  Route<void> route() => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => this,
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      child: child,
    ),
  );

  @override
  State<RewindViewer> createState() => _RewindViewerState();
}

class _RewindViewerState extends State<RewindViewer>
    with WidgetsBindingObserver
    implements RewindNavigator {
  static final _logger = Logger("RewindViewer");
  static const _tapZoneTop = 70 / 844;
  static const _tapZoneBottom = 770 / 844;

  final _starts = <int>[];
  late final int _steps;
  late final int _initialStep;
  final _music = RewindMusic();
  final _shareCards = <String, RewindShareCard>{};
  final _shareButton = GlobalKey();
  ScrollController? _controller;
  double? _height;
  int? _settledStep;
  int? _resizeStep;
  int? _targetStep;
  var _sharing = false;

  @override
  void initState() {
    super.initState();
    var step = 0;
    for (final page in widget.pages) {
      _starts.add(step);
      step += page.stops;
    }
    _steps = step;
    final index = widget.pages.indexWhere(
      (page) => page.key == widget.initialPage,
    );
    _initialStep = index < 0
        ? 0
        : _starts[index] +
              widget.initialStop.clamp(0, widget.pages[index].stops - 1);
    _settle(_initialStep);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_music.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _music.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _music.appActive = state == AppLifecycleState.resumed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: _buildPager),
    );
  }

  Widget _buildPager(BuildContext context, BoxConstraints constraints) {
    final height = constraints.maxHeight;
    if (height == 0) return const SizedBox.shrink();
    final controller = _controllerFor(height);
    return Stack(
      children: [
        GestureDetector(
          onTapUp: (details) => _onTapUp(details, constraints.biggest),
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              if (_resizeStep == null) {
                _settle((controller.offset / height).round());
              }
              return false;
            },
            child: SingleChildScrollView(
              controller: controller,
              physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
              child: SizedBox(
                height: height * _steps,
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final offset = _offset(controller, height);
                    return Stack(
                      children: [
                        Positioned(
                          top: offset,
                          left: 0,
                          right: 0,
                          height: height,
                          child: _buildVisiblePages(
                            _resizeStep?.toDouble() ?? offset / height,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) => _buildChrome(
            context,
            _pageIndexAt((_offset(controller, height) / height).round()),
            constraints.biggest,
          ),
        ),
      ],
    );
  }

  double _offset(ScrollController controller, double height) =>
      (controller.hasClients ? controller.offset : _initialStep * height).clamp(
        0.0,
        (_steps - 1) * height,
      );

  int _pageIndexAt(int step) =>
      _starts.lastIndexWhere((start) => start <= step);

  Widget _buildChrome(BuildContext context, int index, Size size) {
    final page = widget.pages[index];
    final card = _shareCards[page.key];
    final layout = RewindChromeLayout(size, MediaQuery.paddingOf(context));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: page.chrome.onLightPage
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: RewindChromeOverlay(
        layout: layout,
        chrome: page.chrome,
        page: index,
        pageCount: widget.pages.length,
        music: _music,
        shareKey: _shareButton,
        onClose: () => Navigator.of(context).maybePop(),
        onShare: card == null ? null : () => _share(page, card, layout),
      ),
    );
  }

  ScrollController _controllerFor(double height) {
    final controller = _controller;
    final previousHeight = _height;
    _height = height;
    if (controller == null || previousHeight == null) {
      return _controller = ScrollController(
        initialScrollOffset: _initialStep * height,
      );
    }
    if (height != previousHeight && controller.hasClients) {
      final step = (controller.offset / previousHeight).round();
      _resizeStep = step;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (controller.hasClients) controller.jumpTo(step * height);
        _resizeStep = null;
        _settle(step);
      });
    }
    return controller;
  }

  Widget _buildVisiblePages(double scroll) {
    final activeStep = scroll.round();
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.pages.length; i++)
          if (scroll - _starts[i] > -1 &&
              scroll - _starts[i] < widget.pages[i].stops)
            _buildPage(
              widget.pages[i],
              scroll - _starts[i],
              isActive:
                  activeStep >= _starts[i] &&
                  activeStep < _starts[i] + widget.pages[i].stops,
            ),
      ],
    );
  }

  Widget _buildPage(
    RewindPage page,
    double position, {
    required bool isActive,
  }) {
    final content = RewindPageScope(
      page: page,
      navigator: this,
      child: Builder(
        builder: (context) => page.build(context, position, isActive: isActive),
      ),
    );
    final entering = !page.pinned && position < 0;
    return ClipPath(
      key: ValueKey(page.key),
      clipper: _WaveClipper(entering ? 1 + position : 1),
      clipBehavior: entering ? Clip.antiAlias : Clip.none,
      child: content,
    );
  }

  void _settle(int step) {
    if (step == _settledStep) return;
    _settledStep = step;
    final index = _pageIndexAt(step);
    widget.onSettled?.call(widget.pages[index], step - _starts[index]);
  }

  void _onTapUp(TapUpDetails details, Size size) {
    final y = details.localPosition.dy / size.height;
    if (y < _tapZoneTop || y > _tapZoneBottom) return;
    details.localPosition.dx < size.width / 3 ? previous() : next();
  }

  int get _currentStep {
    final controller = _controller;
    final height = _height;
    if (controller == null || height == null || !controller.hasClients) {
      return _initialStep;
    }
    return _targetStep ?? (controller.offset / height).round();
  }

  @override
  void next() {
    final step = _currentStep;
    if (step >= _steps - 1) {
      unawaited(Navigator.of(context).maybePop());
    } else {
      _animateTo(step + 1);
    }
  }

  @override
  void previous() {
    final step = _currentStep;
    if (step > 0) _animateTo(step - 1);
  }

  void _animateTo(int step) {
    final controller = _controller;
    final height = _height;
    if (controller == null || height == null || !controller.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpTo(step * height);
      return;
    }
    _targetStep = step;
    unawaited(
      controller
          .animateTo(
            step * height,
            duration: RewindMotion.waveDuration,
            curve: RewindMotion.wave,
          )
          .whenComplete(() {
            if (_targetStep == step) _targetStep = null;
          }),
    );
  }

  @override
  void attachShareCard(RewindPage page, RewindShareCard card) {
    _shareCards[page.key] = card;
    _refreshChrome();
  }

  @override
  void detachShareCard(RewindPage page, RewindShareCard card) {
    if (_shareCards[page.key] != card) return;
    _shareCards.remove(page.key);
    _refreshChrome();
  }

  void _refreshChrome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _share(
    RewindPage page,
    RewindShareCard card,
    RewindChromeLayout layout,
  ) async {
    if (_sharing) return;
    _sharing = true;
    try {
      await shareRewindCard(
        card,
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
        wordmark: layout.wordmark,
        wordmarkColor: page.chrome.wordmark ?? RewindColors.white,
        origin: shareButtonRect(context, _shareButton),
      );
    } catch (error, stackTrace) {
      _logger.warning("Failed to share ${page.key}", error, stackTrace);
    } finally {
      _sharing = false;
    }
  }
}

class _WaveClipper extends CustomClipper<Path> {
  _WaveClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    final scale = size.width / RewindStage.size.width;
    final amplitude = 16 * sin(pi * progress) * scale;
    final height = size.height;
    final base =
        height +
        amplitude +
        4 * scale -
        progress * (height + 2 * amplitude + 8 * scale);
    final path = Path()..moveTo(-10 * scale, height);
    for (var x = -10.0; x <= RewindStage.size.width + 10; x += 10) {
      path.lineTo(
        x * scale,
        base +
            amplitude * sin(x / RewindStage.size.width * 3 * pi + 5 * progress),
      );
    }
    return path
      ..lineTo((RewindStage.size.width + 10) * scale, height)
      ..close();
  }

  @override
  bool shouldReclip(_WaveClipper oldClipper) => oldClipper.progress != progress;
}
