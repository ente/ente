import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/ui/notification/toast.dart";
import "package:rive/rive.dart" as rive;

class FavoriteWidget extends StatefulWidget {
  final EnteFile file;

  const FavoriteWidget(this.file, {super.key});

  @override
  State<StatefulWidget> createState() => _FavoriteWidgetState();
}

class _FavoriteWidgetState extends State<FavoriteWidget> {
  late Logger _logger;
  bool _isLoading = false;
  bool? _isFavorite;
  late final rive.FileLoader _riveFileLoader;
  rive.StateMachine? _stateMachine;
  bool _hasSetInitialState = false;

  @override
  void initState() {
    super.initState();
    _logger = Logger("_FavoriteWidgetState");
    _riveFileLoader = rive.FileLoader.fromAsset(
      "assets/favorite_icon.riv",
      riveFactory: rive.Factory.rive,
    );
    _initializeFavoriteState();
  }

  Future<void> _initializeFavoriteState() async {
    final isFavorite = await FavoritesService.instance.isFavorite(widget.file);
    if (mounted) {
      setState(() {
        _isFavorite = isFavorite;
      });
      _updateAnimationState();
    }
  }

  @override
  void didUpdateWidget(covariant FavoriteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.uploadedFileID != widget.file.uploadedFileID) {
      _hasSetInitialState = false;
      _initializeFavoriteState();
    }
  }

  @override
  void dispose() {
    _riveFileLoader.dispose();
    super.dispose();
  }

  void _handleRiveLoaded(rive.RiveLoaded loaded) {
    if (!mounted) return;

    _stateMachine = loaded.controller.stateMachine;

    if (_hasSetInitialState) {
      // Re-sync animation state after rebuild (e.g., when loading state clears)
      _updateAnimationState();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _stateMachine == null || _isFavorite == null) return;
        _setInitialAnimationState();
      });
    }
  }

  void _setInitialAnimationState() {
    if (_isFavorite == null || _hasSetInitialState) return;
    _hasSetInitialState = true;
    _updateAnimationState();
  }

  void _updateAnimationState() {
    if (_isFavorite == null || _stateMachine == null) return;
    if (_isFavorite!) {
      _stateMachine!.trigger("Filled")?.fire();
    } else {
      _stateMachine!.trigger("Stroke")?.fire();
    }
  }

  Future<void> _onTap() async {
    if (_isLoading || _isFavorite == null || _stateMachine == null) return;

    final bool currentlyFavorite = _isFavorite!;
    final bool newFavoriteState = !currentlyFavorite;

    if (widget.file.uploadedFileID == null) {
      setState(() {
        _isLoading = true;
      });
    }

    bool hasError = false;

    if (newFavoriteState) {
      // Adding to favorites - play animation
      _stateMachine?.trigger("Animation to filled")?.fire();

      try {
        await FavoritesService.instance.addToFavorites(
          context,
          widget.file.copyWith(),
        );
        _stateMachine?.trigger("Filled")?.fire();
      } catch (e, s) {
        _logger.severe("Failed to add file to favorites", e, s);
        hasError = true;
        if (!mounted) return;
        showToast(
          context,
          AppLocalizations.of(context).sorryCouldNotAddToFavorites,
        );
        _stateMachine?.trigger("Stroke")?.fire();
      }
    } else {
      // Removing from favorites - go directly to stroke
      _stateMachine?.trigger("Stroke")?.fire();

      try {
        await FavoritesService.instance.removeFromFavorites(
          context,
          widget.file.copyWith(),
        );
      } catch (e, s) {
        _logger.severe("Failed to remove file from favorites", e, s);
        hasError = true;
        if (!mounted) return;
        showToast(
          context,
          AppLocalizations.of(context).sorryCouldNotRemoveFromFavorites,
        );
        _stateMachine?.trigger("Filled")?.fire();
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (!hasError) {
        _isFavorite = newFavoriteState;
      }
    });

    if (newFavoriteState && !hasError) {
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show blank while initial state is being fetched
    if (_isFavorite == null || _isLoading) {
      return const SizedBox(width: 22, height: 22);
    }

    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        width: 34,
        height: 30,
        child: rive.RiveWidgetBuilder(
          fileLoader: _riveFileLoader,
          stateMachineSelector: const rive.StateMachineNamed("State Machine 1"),
          onLoaded: _handleRiveLoaded,
          builder: (BuildContext context, rive.RiveState state) {
            if (state is rive.RiveLoaded) {
              return rive.RiveWidget(
                controller: state.controller,
                fit: rive.Fit.contain,
              );
            }
            if (state is rive.RiveFailed) {
              _logger.warning("Failed to load Rive file: ${state.error}");
            }
            // Loading state
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
