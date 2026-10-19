import "dart:async";
import "dart:math" as math;

import "package:ente_icons/ente_icons.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/notification/toast.dart";

class FavoriteWidget extends StatefulWidget {
  final EnteFile file;
  final double? iconSize;
  final double? tapTargetSize;

  const FavoriteWidget(
    this.file, {
    this.iconSize,
    this.tapTargetSize,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _FavoriteWidgetState();
}

class _FavoriteWidgetState extends State<FavoriteWidget>
    with SingleTickerProviderStateMixin {
  static const double _defaultIconSize = 20;

  late final Logger _logger;
  late final AnimationController _favoriteAnimationController;
  late final Animation<double> _favoriteScaleAnimation;

  bool _isUpdating = false;
  bool? _isFavorite;
  int _fileVersion = 0;
  late final StreamSubscription<LocalPhotosUpdatedEvent>
  _favoriteUpdatesSubscription;

  @override
  void initState() {
    super.initState();
    _logger = Logger("_FavoriteWidgetState");
    _favoriteAnimationController = AnimationController(
      duration: const Duration(milliseconds: 960),
      vsync: this,
    );
    _favoriteScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0.72,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.72,
          end: 1.32,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.32,
          end: 0.86,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.86,
          end: 1.16,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.16,
          end: 0.96,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 13,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.96,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 12,
      ),
    ]).animate(_favoriteAnimationController);
    _favoriteUpdatesSubscription = Bus.instance
        .on<LocalPhotosUpdatedEvent>()
        .where(
          (event) =>
              event.source == "favoriteAdd" || event.source == "favoriteRemove",
        )
        .listen((event) {
          if (event.updatedFiles.any(
            (file) => file.uploadedFileID == widget.file.uploadedFileID,
          )) {
            _initializeFavoriteState();
          }
        });
    _initializeFavoriteState();
  }

  Future<void> _initializeFavoriteState() async {
    final int fileVersion = _fileVersion;
    final isFavorite = await FavoritesService.instance.isFavorite(widget.file);
    if (!mounted || fileVersion != _fileVersion) return;
    setState(() {
      _isFavorite = isFavorite;
    });
  }

  @override
  void didUpdateWidget(covariant FavoriteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.uploadedFileID != widget.file.uploadedFileID) {
      _fileVersion++;
      _isUpdating = false;
      _isFavorite = null;
      _favoriteAnimationController.reset();
      _initializeFavoriteState();
    }
  }

  @override
  void dispose() {
    _favoriteUpdatesSubscription.cancel();
    _favoriteAnimationController.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_isUpdating || _isFavorite == null) return;

    final int fileVersion = _fileVersion;
    final file = widget.file.copyWith();
    final bool previousFavoriteState = _isFavorite!;
    final bool newFavoriteState = !previousFavoriteState;

    setState(() {
      _isUpdating = true;
      _isFavorite = newFavoriteState;
    });

    if (newFavoriteState) {
      unawaited(_favoriteAnimationController.forward(from: 0));
    } else {
      _favoriteAnimationController.reset();
    }

    try {
      if (newFavoriteState) {
        await FavoritesService.instance.addToFavorites(context, file);
      } else {
        await FavoritesService.instance.removeFromFavorites(context, file);
      }
    } catch (e, s) {
      _logger.severe(
        newFavoriteState
            ? "Failed to add file to favorites"
            : "Failed to remove file from favorites",
        e,
        s,
      );
      if (!mounted || fileVersion != _fileVersion) return;
      _favoriteAnimationController.reset();
      setState(() {
        _isUpdating = false;
        _isFavorite = previousFavoriteState;
      });
      showToast(
        context,
        newFavoriteState
            ? context.strings.sorryCouldNotAddToFavorites
            : context.strings.sorryCouldNotRemoveFromFavorites,
      );
      return;
    }

    if (!mounted || fileVersion != _fileVersion) return;
    setState(() {
      _isUpdating = false;
    });

    if (newFavoriteState) {
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  @override
  Widget build(BuildContext context) {
    final double placeholderSize = widget.tapTargetSize ?? 22;
    if (_isFavorite == null) {
      return SizedBox.square(dimension: placeholderSize);
    }

    final double iconSize =
        widget.iconSize ?? widget.tapTargetSize ?? _defaultIconSize;
    final colorScheme = getEnteColorScheme(context);
    final animatedIcon = SizedBox.square(
      dimension: iconSize,
      child: AnimatedBuilder(
        animation: _favoriteAnimationController,
        builder: (context, child) {
          final bool hasFavoriteAnimationStarted =
              _isFavorite! &&
              (_favoriteAnimationController.isAnimating ||
                  _favoriteAnimationController.isCompleted);
          final double colorFadeProgress =
              ((_favoriteAnimationController.value - 0.72) / 0.28).clamp(
                0.0,
                1.0,
              );
          final Color iconColor = hasFavoriteAnimationStarted
              ? Color.lerp(
                  colorScheme.primary400,
                  Colors.white,
                  Curves.easeInOutCubic.transform(colorFadeProgress),
                )!
              : Colors.white;
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _FavoriteBurstPainter(
                    progress: _favoriteAnimationController.value,
                    primaryColor: colorScheme.primary400,
                    secondaryColor: colorScheme.primary700,
                  ),
                ),
              ),
              Transform.scale(
                scale: _favoriteScaleAnimation.value,
                child: IconTheme(
                  data: IconThemeData(color: iconColor),
                  child: child!,
                ),
              ),
            ],
          );
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: Icon(
            _isFavorite! ? EnteIcons.favoriteFilled : EnteIcons.favoriteStroke,
            key: ValueKey(_isFavorite),
            size: iconSize,
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      toggled: _isFavorite!,
      label: _isFavorite!
          ? context.strings.removeFromFavorite
          : context.strings.favorite,
      child: GestureDetector(
        onTap: _onTap,
        behavior: HitTestBehavior.opaque,
        child: widget.iconSize != null || widget.tapTargetSize != null
            ? SizedBox.square(
                dimension: widget.tapTargetSize ?? widget.iconSize!,
                child: Center(child: animatedIcon),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                width: 34,
                height: 30,
                child: Center(child: animatedIcon),
              ),
      ),
    );
  }
}

class _FavoriteBurstPainter extends CustomPainter {
  static const double _diagonalDirection = 0.7071067811865476;
  static const List<Offset> _particleDirections = [
    Offset(0, -1),
    Offset(_diagonalDirection, -_diagonalDirection),
    Offset(1, 0),
    Offset(_diagonalDirection, _diagonalDirection),
    Offset(0, 1),
    Offset(-_diagonalDirection, _diagonalDirection),
    Offset(-1, 0),
    Offset(-_diagonalDirection, -_diagonalDirection),
  ];

  final double progress;
  final Color primaryColor;
  final Color secondaryColor;

  const _FavoriteBurstPainter({
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double burstProgress = ((progress - 0.12) / 0.7).clamp(0.0, 1.0);
    if (burstProgress <= 0 || burstProgress >= 1) return;

    final center = size.center(Offset.zero);
    final double shortestSide = size.shortestSide;
    final double easedProgress = Curves.easeOutCubic.transform(burstProgress);
    final double opacity = math.sin(burstProgress * math.pi);
    final double startRadius = shortestSide * 0.3;
    final double endRadius = shortestSide * 0.48;
    final double radius =
        startRadius + ((endRadius - startRadius) * easedProgress);
    final double particleRadius = shortestSide * 0.035;
    final double halfLineLength = shortestSide * 0.045;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = shortestSide * 0.06;

    for (int index = 0; index < _particleDirections.length; index++) {
      final direction = _particleDirections[index];
      final particleCenter = center + (direction * radius);
      final Color particleColor = switch (index % 3) {
        0 => primaryColor,
        1 => Colors.white,
        _ => secondaryColor,
      };
      paint.color = particleColor.withValues(alpha: opacity);

      if (index.isEven) {
        canvas.drawCircle(particleCenter, particleRadius, paint);
      } else {
        canvas.drawLine(
          particleCenter - (direction * halfLineLength),
          particleCenter + (direction * halfLineLength),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FavoriteBurstPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        primaryColor != oldDelegate.primaryColor ||
        secondaryColor != oldDelegate.secondaryColor;
  }
}
