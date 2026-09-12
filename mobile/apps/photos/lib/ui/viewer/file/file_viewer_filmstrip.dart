import "dart:async";
import "dart:math";

import "package:flutter/material.dart";
import "package:flutter/rendering.dart" show ScrollCacheExtent;
import "package:flutter/services.dart";
import "package:photos/ui/viewer/file/file_viewer_filmstrip_event.dart";
import "package:photos/ui/viewer/file/file_viewer_filmstrip_physics.dart";

const fileViewerFilmstripKey = ValueKey<String>("file-viewer-filmstrip");
const fileViewerFilmstripListKey = ValueKey<String>(
  "file-viewer-filmstrip-list",
);

@immutable
class FileViewerFilmstripLayout {
  static const compact = FileViewerFilmstripLayout._(
    scale: 1,
    height: 45,
    itemExtent: 33,
    selectedThumbnailSize: Size(34, 43),
    thumbnailSize: Size(29, 35),
    thumbnailBorderRadius: BorderRadius.all(Radius.circular(2.5)),
  );
  static const _compactShortestSide = 600.0;
  static const _maximumScale = 1.5;

  final double scale;
  final double height;
  final double itemExtent;
  final Size selectedThumbnailSize;
  final Size thumbnailSize;
  final BorderRadius thumbnailBorderRadius;

  const FileViewerFilmstripLayout._({
    required this.scale,
    required this.height,
    required this.itemExtent,
    required this.selectedThumbnailSize,
    required this.thumbnailSize,
    required this.thumbnailBorderRadius,
  });

  factory FileViewerFilmstripLayout.forAvailableSize(Size availableSize) {
    final shortestSide = min(availableSize.width, availableSize.height);
    final scale = (shortestSide / _compactShortestSide)
        .clamp(1.0, _maximumScale)
        .toDouble();
    if (scale == 1) return compact;
    return FileViewerFilmstripLayout._(
      scale: scale,
      height: compact.height * scale,
      itemExtent: compact.itemExtent * scale,
      selectedThumbnailSize: compact.selectedThumbnailSize * scale,
      thumbnailSize: compact.thumbnailSize * scale,
      thumbnailBorderRadius: BorderRadius.all(Radius.circular(2.5 * scale)),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileViewerFilmstripLayout && scale == other.scale;

  @override
  int get hashCode => scale.hashCode;
}

const _cacheExtentInItems = 4;
const _scrollAnimationDuration = Duration(milliseconds: 180);

typedef FileViewerFilmstripSemanticValueBuilder =
    String Function(int current, int total);

class FileViewerFilmstrip extends StatefulWidget {
  final int itemCount;
  final int selectedIndex;
  final IndexedWidgetBuilder itemBuilder;
  final Key? Function(int index)? itemKeyBuilder;
  final int? Function(Key key)? findChildIndexCallback;
  final FileViewerFilmstripEventCallback onEvent;
  final String? semanticLabel;
  final FileViewerFilmstripSemanticValueBuilder semanticValueBuilder;
  final FileViewerFilmstripLayout layout;

  const FileViewerFilmstrip({
    required this.itemCount,
    required this.selectedIndex,
    required this.itemBuilder,
    required this.onEvent,
    required this.semanticValueBuilder,
    this.itemKeyBuilder,
    this.findChildIndexCallback,
    this.semanticLabel,
    this.layout = FileViewerFilmstripLayout.compact,
    super.key = fileViewerFilmstripKey,
  }) : assert(itemCount >= 0);

  @override
  State<FileViewerFilmstrip> createState() => _FileViewerFilmstripState();
}

class _FileViewerFilmstripState extends State<FileViewerFilmstrip> {
  late final ScrollController _scrollController;
  late final ValueNotifier<int> _focusedIndexNotifier;
  final _interaction = _FilmstripInteractionState();

  int get _focusedIndex => _focusedIndexNotifier.value;

  @override
  void initState() {
    super.initState();
    _focusedIndexNotifier = ValueNotifier(_clampIndex(widget.selectedIndex));
    _scrollController = ScrollController(
      initialScrollOffset: _offsetForIndex(_focusedIndex),
    );
    _scrollController.addListener(_onScrollOffsetChanged);
  }

  @override
  void didUpdateWidget(covariant FileViewerFilmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedIndex = _clampIndex(widget.selectedIndex);
    final itemCountChanged = widget.itemCount != oldWidget.itemCount;
    final layoutChanged = widget.layout != oldWidget.layout;
    final shouldSyncFocus =
        !_interaction.isUserScrollSessionActive ||
        _focusedIndex >= widget.itemCount;
    final focusChanged = shouldSyncFocus && _setFocusedIndex(selectedIndex);

    if (layoutChanged) {
      _requestCentering(jump: true);
    } else if (!_interaction.isUserScrollSessionActive &&
        (focusChanged || itemCountChanged)) {
      _requestCentering();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollOffsetChanged);
    _scrollController.dispose();
    _focusedIndexNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<int>(
      valueListenable: _focusedIndexNotifier,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = max(
              0.0,
              (constraints.maxWidth - widget.layout.itemExtent) / 2,
            );
            return Listener(
              onPointerDown: (event) => _interaction.pointerDown(event.pointer),
              onPointerUp: _onPointerEnded,
              onPointerCancel: _onPointerEnded,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: SizedBox(
                  height: widget.layout.height,
                  child: ListView.builder(
                    key: fileViewerFilmstripListKey,
                    controller: _scrollController,
                    clipBehavior: Clip.none,
                    scrollDirection: Axis.horizontal,
                    physics: fileViewerFilmstripPhysics,
                    itemCount: widget.itemCount,
                    itemExtent: widget.layout.itemExtent,
                    findChildIndexCallback: widget.findChildIndexCallback,
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    scrollCacheExtent: ScrollCacheExtent.pixels(
                      widget.layout.itemExtent * _cacheExtentInItems,
                    ),
                    addAutomaticKeepAlives: false,
                    addSemanticIndexes: false,
                    itemBuilder: (context, index) => _buildItem(context, index),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      builder: (context, focusedIndex, child) {
        final clampedFocusedIndex = _clampIndex(focusedIndex);
        return Semantics(
          container: true,
          label: widget.semanticLabel,
          value: widget.semanticValueBuilder(
            clampedFocusedIndex + 1,
            widget.itemCount,
          ),
          increasedValue: clampedFocusedIndex < widget.itemCount - 1
              ? widget.semanticValueBuilder(
                  clampedFocusedIndex + 2,
                  widget.itemCount,
                )
              : null,
          decreasedValue: clampedFocusedIndex > 0
              ? widget.semanticValueBuilder(
                  clampedFocusedIndex,
                  widget.itemCount,
                )
              : null,
          onIncrease: clampedFocusedIndex < widget.itemCount - 1
              ? () => _selectIndex(
                  clampedFocusedIndex + 1,
                  FileViewerFilmstripEventType.tap,
                )
              : null,
          onDecrease: clampedFocusedIndex > 0
              ? () => _selectIndex(
                  clampedFocusedIndex - 1,
                  FileViewerFilmstripEventType.tap,
                )
              : null,
          child: child,
        );
      },
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectIndex(index, FileViewerFilmstripEventType.tap),
      child: SizedBox(
        width: widget.layout.itemExtent,
        height: widget.layout.height,
        child: OverflowBox(
          minWidth: 0,
          maxWidth: widget.layout.selectedThumbnailSize.width,
          minHeight: 0,
          maxHeight: widget.layout.selectedThumbnailSize.height,
          child: _FilmstripThumbnailFrame(
            scrollPosition: _scrollController,
            proximity: () => _centerProximity(index),
            layout: widget.layout,
            child: widget.itemBuilder(context, index),
          ),
        ),
      ),
    );
    final key = widget.itemKeyBuilder?.call(index);
    return key == null ? item : KeyedSubtree(key: key, child: item);
  }

  bool _onScrollNotification(ScrollNotification notification) {
    // Notifications delimit the drag + ballistic lifecycle. The controller
    // listener updates focus from offsets so thumbnail visuals do not trail
    // scrolling by a rendered frame.
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _beginUserScrollSession();
    }

    if (notification is ScrollEndNotification) {
      _finishScrollActivity();
    }
    return false;
  }

  void _beginUserScrollSession() {
    _interaction.beginUserScrollSession();
    _emitEvent(_focusedIndex, FileViewerFilmstripEventType.scrubStart);
  }

  void _finishScrollActivity() {
    if (_interaction.isUserScrollSessionActive) {
      final finalIndex = _updateFocusFromScrollOffset();
      _interaction.endUserScrollSession();
      _emitEvent(finalIndex, FileViewerFilmstripEventType.scrubCommit);
    }
    _requestCentering();
  }

  int _updateFocusFromScrollOffset() {
    final index = _nearestScrolledIndex();
    if (index != _focusedIndex) {
      _selectIndex(
        index,
        FileViewerFilmstripEventType.scrubPreview,
        animateToCenter: false,
      );
    }
    return index;
  }

  void _onScrollOffsetChanged() {
    if (_interaction.isUserScrollSessionActive) {
      _updateFocusFromScrollOffset();
    }
  }

  void _onPointerEnded(PointerEvent event) {
    if (_interaction.pointerEnded(event.pointer)) {
      _requestCentering();
    }
  }

  int _nearestScrolledIndex() {
    if (!_scrollController.hasClients || widget.itemCount == 0) return 0;
    return _clampIndex(
      (_scrollController.offset / widget.layout.itemExtent).round(),
    );
  }

  void _selectIndex(
    int index,
    FileViewerFilmstripEventType type, {
    bool animateToCenter = true,
  }) {
    final clampedIndex = _clampIndex(index);
    final focusChanged = _setFocusedIndex(clampedIndex);
    final shouldNotify =
        focusChanged || clampedIndex != _clampIndex(widget.selectedIndex);
    if (shouldNotify) {
      _emitEvent(clampedIndex, type, withHaptic: true);
    }
    if (animateToCenter) _animateToIndex(clampedIndex);
  }

  bool _setFocusedIndex(int index) {
    if (index == _focusedIndex) return false;
    _focusedIndexNotifier.value = index;
    return true;
  }

  void _emitEvent(
    int index,
    FileViewerFilmstripEventType type, {
    bool withHaptic = false,
  }) {
    if (withHaptic) unawaited(HapticFeedback.selectionClick());
    widget.onEvent((index: index, type: type));
  }

  double _centerProximity(int index) {
    var scrollOffset = _offsetForIndex(_focusedIndex);
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      scrollOffset = position.hasContentDimensions
          ? position.pixels
                .clamp(position.minScrollExtent, position.maxScrollExtent)
                .toDouble()
          : position.pixels;
    }
    final linearProximity =
        (1 -
                ((scrollOffset - _offsetForIndex(index)).abs() /
                    widget.layout.itemExtent))
            .clamp(0.0, 1.0)
            .toDouble();
    // Smoothstep avoids a visible change in slope as an item enters or leaves
    // the centered state.
    return linearProximity * linearProximity * (3 - (2 * linearProximity));
  }

  bool _jumpOnNextCentering = false;

  void _requestCentering({bool jump = false}) {
    _jumpOnNextCentering |= jump;
    if (widget.itemCount == 0 || !_interaction.tryScheduleCentering()) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_interaction.resolveScheduledCentering()) return;
      if (_jumpOnNextCentering) {
        _jumpOnNextCentering = false;
        _jumpToIndex(_focusedIndex);
      } else {
        _animateToIndex(_focusedIndex);
      }
    });
  }

  void _jumpToIndex(int index) {
    if (widget.itemCount == 0 || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = _offsetForIndex(
      _clampIndex(index),
    ).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((position.pixels - target).abs() < 0.5) return;
    _scrollController.jumpTo(target);
  }

  void _animateToIndex(int index) {
    if (widget.itemCount == 0 || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = _offsetForIndex(
      _clampIndex(index),
    ).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((position.pixels - target).abs() < 0.5) return;
    unawaited(
      _scrollController.animateTo(
        target,
        duration: _scrollAnimationDuration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  int _clampIndex(int index) {
    if (widget.itemCount == 0) return 0;
    return index.clamp(0, widget.itemCount - 1);
  }

  double _offsetForIndex(int index) => index * widget.layout.itemExtent;
}

enum _CenteringRequestState { idle, scheduled, deferred }

class _FilmstripInteractionState {
  // Pointer state is independent from the scroll session: touching a coasting
  // strip can end its ballistic activity before the replacement drag starts.
  final Set<int> _activePointerIds = {};

  bool _userScrollSessionActive = false;

  _CenteringRequestState _centeringState = _CenteringRequestState.idle;

  bool get isUserScrollSessionActive => _userScrollSessionActive;

  bool get _blocksCentering =>
      _userScrollSessionActive || _activePointerIds.isNotEmpty;

  void pointerDown(int pointerId) => _activePointerIds.add(pointerId);

  bool pointerEnded(int pointerId) {
    _activePointerIds.remove(pointerId);
    return !_blocksCentering &&
        _centeringState == _CenteringRequestState.deferred;
  }

  void beginUserScrollSession() {
    _userScrollSessionActive = true;
  }

  void endUserScrollSession() {
    _userScrollSessionActive = false;
  }

  bool tryScheduleCentering() {
    if (_centeringState == _CenteringRequestState.scheduled) return false;
    _centeringState = _CenteringRequestState.scheduled;
    return true;
  }

  bool resolveScheduledCentering() {
    assert(_centeringState == _CenteringRequestState.scheduled);
    if (_blocksCentering) {
      _centeringState = _CenteringRequestState.deferred;
      return false;
    }
    _centeringState = _CenteringRequestState.idle;
    return true;
  }
}

class _FilmstripThumbnailFrame extends AnimatedWidget {
  final ValueGetter<double> proximity;
  final FileViewerFilmstripLayout layout;
  final Widget child;

  const _FilmstripThumbnailFrame({
    required Listenable scrollPosition,
    required this.proximity,
    required this.layout,
    required this.child,
  }) : super(listenable: scrollPosition);

  @override
  Widget build(BuildContext context) {
    final centerProximity = proximity();
    final size = Size.lerp(
      layout.thumbnailSize,
      layout.selectedThumbnailSize,
      centerProximity,
    )!;
    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: layout.thumbnailBorderRadius,
          boxShadow: [
            BoxShadow(
              color: Color.lerp(
                const Color(0x24000000),
                const Color(0x33000000),
                centerProximity,
              )!,
              blurRadius: (2 + centerProximity) * layout.scale,
              offset: Offset(0, layout.scale),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: layout.thumbnailBorderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              ColoredBox(
                color: Color.lerp(
                  Colors.black26,
                  Colors.transparent,
                  centerProximity,
                )!,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
