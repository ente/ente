// Flutter's Scrollbar modified to report when its thumb is in use.

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import "package:flutter/material.dart";

const double _kScrollbarThickness = 8.0;
const double _kScrollbarThicknessWithTrack = 12.0;
const double _kScrollbarMargin = 2.0;
const Radius _kScrollbarRadius = Radius.circular(8.0);
const Duration _kScrollbarFadeDuration = Duration(milliseconds: 300);
const Duration _kScrollbarTimeToFade = Duration(milliseconds: 600);

class ScrollbarWithUseNotifer extends StatelessWidget {
  const ScrollbarWithUseNotifer({
    super.key,
    required this.child,
    required this.inUseNotifier,
    required this.minScrollbarLength,
    this.controller,
    this.thumbVisibility,
    this.trackVisibility,
    this.thickness,
    this.radius,
    this.notificationPredicate,
    this.interactive,
    this.scrollbarOrientation,
    this.showThumb,
    this.scrollbarPadding,
  });

  final Widget child;

  final ScrollController? controller;

  final bool? thumbVisibility;

  final bool? trackVisibility;

  final double? thickness;

  final Radius? radius;

  final bool? interactive;

  final ScrollNotificationPredicate? notificationPredicate;

  final ScrollbarOrientation? scrollbarOrientation;

  final ValueNotifier<bool> inUseNotifier;

  final double minScrollbarLength;

  final bool? showThumb;

  final EdgeInsets? scrollbarPadding;

  @override
  Widget build(BuildContext context) {
    return ScrollbarTheme(
      data: ScrollbarTheme.of(context).copyWith(
        thumbColor: Theme.of(context).brightness == Brightness.dark
            ? const WidgetStatePropertyAll(Color.fromARGB(244, 215, 215, 215))
            : WidgetStateProperty.resolveWith((Set<WidgetState> states) {
                if (states.contains(WidgetState.dragged)) {
                  return const Color.fromARGB(243, 143, 143, 143);
                }

                return const Color.fromARGB(244, 199, 199, 199);
              }),
      ),
      child: _MaterialScrollbar(
        controller: controller,
        thumbVisibility: thumbVisibility,
        trackVisibility: trackVisibility,
        thickness: thickness,
        radius: radius,
        notificationPredicate: notificationPredicate,
        interactive: interactive,
        scrollbarOrientation: scrollbarOrientation,
        inUseNotifier: inUseNotifier,
        minScrollbarLength: minScrollbarLength,
        showThumb: showThumb,
        scrollbarPadding: scrollbarPadding,
        child: child,
      ),
    );
  }
}

class _MaterialScrollbar extends RawScrollbar {
  final ValueNotifier<bool> inUseNotifier;
  final double minScrollbarLength;
  final bool? showThumb;
  final EdgeInsets? scrollbarPadding;
  const _MaterialScrollbar({
    required super.child,
    required this.inUseNotifier,
    required this.minScrollbarLength,
    required this.showThumb,
    required this.scrollbarPadding,
    super.controller,
    super.thumbVisibility,
    super.trackVisibility,
    super.thickness,
    super.radius,
    ScrollNotificationPredicate? notificationPredicate,
    super.interactive,
    super.scrollbarOrientation,
  }) : super(
         fadeDuration: _kScrollbarFadeDuration,
         timeToFade: _kScrollbarTimeToFade,
         pressDuration: Duration.zero,
         notificationPredicate:
             notificationPredicate ?? defaultScrollNotificationPredicate,
       );

  @override
  _MaterialScrollbarState createState() => _MaterialScrollbarState();
}

class _MaterialScrollbarState extends RawScrollbarState<_MaterialScrollbar> {
  late AnimationController _hoverAnimationController;
  bool _dragIsActive = false;
  bool _hoverIsActive = false;
  late ColorScheme _colorScheme;
  late ScrollbarThemeData _scrollbarTheme;
  late bool _useAndroidScrollbar;

  @override
  bool get showScrollbar =>
      widget.thumbVisibility ??
      _scrollbarTheme.thumbVisibility?.resolve(_states) ??
      false;

  @override
  bool get enableGestures =>
      widget.interactive ??
      _scrollbarTheme.interactive ??
      !_useAndroidScrollbar;

  WidgetStateProperty<bool> get _trackVisibility =>
      WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        return widget.trackVisibility ??
            _scrollbarTheme.trackVisibility?.resolve(states) ??
            false;
      });

  Set<WidgetState> get _states => <WidgetState>{
    if (_dragIsActive) WidgetState.dragged,
    if (_hoverIsActive) WidgetState.hovered,
  };

  WidgetStateProperty<Color> get _thumbColor {
    if (widget.showThumb == false) {
      return WidgetStateProperty.all(const Color(0x00000000));
    }
    final Color onSurface = _colorScheme.onSurface;
    final Brightness brightness = _colorScheme.brightness;
    late Color dragColor;
    late Color hoverColor;
    late Color idleColor;
    switch (brightness) {
      case Brightness.light:
        dragColor = onSurface.withValues(alpha: 0.6);
        hoverColor = onSurface.withValues(alpha: 0.5);
        idleColor = _useAndroidScrollbar
            ? Theme.of(context).highlightColor.withValues(alpha: 1.0)
            : onSurface.withValues(alpha: 0.1);
      case Brightness.dark:
        dragColor = onSurface.withValues(alpha: 0.75);
        hoverColor = onSurface.withValues(alpha: 0.65);
        idleColor = _useAndroidScrollbar
            ? Theme.of(context).highlightColor.withValues(alpha: 1.0)
            : onSurface.withValues(alpha: 0.3);
    }

    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.dragged)) {
        return _scrollbarTheme.thumbColor?.resolve(states) ?? dragColor;
      }

      // A visible track changes the thumb color without the hover animation.
      if (_trackVisibility.resolve(states)) {
        return _scrollbarTheme.thumbColor?.resolve(states) ?? hoverColor;
      }

      return Color.lerp(
        _scrollbarTheme.thumbColor?.resolve(states) ?? idleColor,
        _scrollbarTheme.thumbColor?.resolve(states) ?? hoverColor,
        _hoverAnimationController.value,
      )!;
    });
  }

  WidgetStateProperty<Color> get _trackColor {
    if (widget.showThumb == false) {
      return WidgetStateProperty.all(const Color(0x00000000));
    }
    final Color onSurface = _colorScheme.onSurface;
    final Brightness brightness = _colorScheme.brightness;
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (showScrollbar && _trackVisibility.resolve(states)) {
        return _scrollbarTheme.trackColor?.resolve(states) ??
            switch (brightness) {
              Brightness.light => onSurface.withValues(alpha: 0.03),
              Brightness.dark => onSurface.withValues(alpha: 0.05),
            };
      }
      return const Color(0x00000000);
    });
  }

  WidgetStateProperty<Color> get _trackBorderColor {
    if (widget.showThumb == false) {
      return WidgetStateProperty.all(const Color(0x00000000));
    }
    final Color onSurface = _colorScheme.onSurface;
    final Brightness brightness = _colorScheme.brightness;
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (showScrollbar && _trackVisibility.resolve(states)) {
        return _scrollbarTheme.trackBorderColor?.resolve(states) ??
            switch (brightness) {
              Brightness.light => onSurface.withValues(alpha: 0.1),
              Brightness.dark => onSurface.withValues(alpha: 0.25),
            };
      }
      return const Color(0x00000000);
    });
  }

  WidgetStateProperty<double> get _thickness {
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.hovered) &&
          _trackVisibility.resolve(states)) {
        return widget.thickness ??
            _scrollbarTheme.thickness?.resolve(states) ??
            _kScrollbarThicknessWithTrack;
      }
      return widget.thickness ??
          _scrollbarTheme.thickness?.resolve(states) ??
          (_kScrollbarThickness / (_useAndroidScrollbar ? 2 : 1));
    });
  }

  @override
  void initState() {
    super.initState();
    _hoverAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _hoverAnimationController.addListener(() {
      updateScrollbarPainter();
    });
  }

  @override
  void didChangeDependencies() {
    final ThemeData theme = Theme.of(context);
    _colorScheme = theme.colorScheme;
    _scrollbarTheme = ScrollbarTheme.of(context);
    switch (theme.platform) {
      case TargetPlatform.android:
        _useAndroidScrollbar = true;
      case TargetPlatform.iOS:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        _useAndroidScrollbar = false;
    }
    super.didChangeDependencies();
  }

  @override
  void updateScrollbarPainter() {
    scrollbarPainter
      ..color = _thumbColor.resolve(_states)
      ..trackColor = _trackColor.resolve(_states)
      ..trackBorderColor = _trackBorderColor.resolve(_states)
      ..textDirection = Directionality.of(context)
      ..thickness = _thickness.resolve(_states)
      ..radius =
          widget.radius ??
          _scrollbarTheme.radius ??
          (_useAndroidScrollbar ? null : _kScrollbarRadius)
      ..crossAxisMargin =
          _scrollbarTheme.crossAxisMargin ??
          (_useAndroidScrollbar ? 0.0 : _kScrollbarMargin)
      ..mainAxisMargin = _scrollbarTheme.mainAxisMargin ?? 0.0
      ..minLength = widget.minScrollbarLength
      ..padding = widget.scrollbarPadding ?? MediaQuery.paddingOf(context)
      ..scrollbarOrientation = widget.scrollbarOrientation
      ..ignorePointer = !enableGestures;
  }

  @override
  void handleThumbPressStart(Offset localPosition) {
    super.handleThumbPressStart(localPosition);
    setState(() {
      _dragIsActive = true;
      widget.inUseNotifier.value = true;
    });
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    super.handleThumbPressEnd(localPosition, velocity);
    setState(() {
      _dragIsActive = false;
      widget.inUseNotifier.value = false;
    });
  }

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    if (isPointerOverScrollbar(event.position, event.kind, forHover: true)) {
      setState(() {
        _hoverIsActive = true;
      });
      _hoverAnimationController.forward();
    } else if (_hoverIsActive) {
      setState(() {
        _hoverIsActive = false;
      });
      _hoverAnimationController.reverse();
    }
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    setState(() {
      _hoverIsActive = false;
    });
    _hoverAnimationController.reverse();
  }

  @override
  void dispose() {
    _hoverAnimationController.dispose();
    super.dispose();
  }
}
