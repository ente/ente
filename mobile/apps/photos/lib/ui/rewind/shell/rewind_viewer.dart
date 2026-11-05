import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";

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

  @override
  State<RewindViewer> createState() => _RewindViewerState();
}

class _RewindViewerState extends State<RewindViewer> {
  final _starts = <int>[];
  late final int _steps;
  late final int _initialStep;
  ScrollController? _controller;
  double? _height;
  int? _settledStep;
  int? _resizeStep;

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
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            LayoutBuilder(builder: _buildPager),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPager(BuildContext context, BoxConstraints constraints) {
    final height = constraints.maxHeight;
    if (height == 0) return const SizedBox.shrink();
    final controller = _controllerFor(height);
    return NotificationListener<ScrollEndNotification>(
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
              final offset =
                  (controller.hasClients
                          ? controller.offset
                          : _initialStep * height)
                      .clamp(0.0, (_steps - 1) * height);
              return Stack(
                children: [
                  Positioned(
                    top: offset,
                    left: 0,
                    right: 0,
                    height: height,
                    child: _buildVisiblePages(
                      context,
                      _resizeStep?.toDouble() ?? offset / height,
                      height,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
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

  Widget _buildVisiblePages(
    BuildContext context,
    double scroll,
    double height,
  ) {
    final activeStep = scroll.round();
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.pages.length; i++)
          if (scroll - _starts[i] > -1 &&
              scroll - _starts[i] < widget.pages[i].stops)
            _buildPage(
              context,
              widget.pages[i],
              scroll - _starts[i],
              height,
              isActive:
                  activeStep >= _starts[i] &&
                  activeStep < _starts[i] + widget.pages[i].stops,
            ),
      ],
    );
  }

  Widget _buildPage(
    BuildContext context,
    RewindPage page,
    double position,
    double height, {
    required bool isActive,
  }) {
    final lastStop = page.stops - 1;
    final double shift = page.pinned
        ? 0
        : position < 0
        ? -position
        : position > lastStop
        ? lastStop - position
        : 0;
    return Transform.translate(
      key: ValueKey(page.key),
      offset: Offset(0, shift * height),
      child: page.build(context, position, isActive: isActive),
    );
  }

  void _settle(int step) {
    if (step == _settledStep) return;
    _settledStep = step;
    final index = _starts.lastIndexWhere((start) => start <= step);
    widget.onSettled?.call(widget.pages[index], step - _starts[index]);
  }
}
