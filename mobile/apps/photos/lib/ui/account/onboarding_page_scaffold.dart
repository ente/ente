import "dart:async";
import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/settings/developer_settings_tap_area.dart";
import "package:rive/rive.dart" as rive;

enum OnboardingIllustration {
  login("assets/onboarding_login.riv", 0.535, -30.8, 3.9),
  signUp("assets/onboarding_login.riv", 0.44, -53.9, 3.6),
  email("assets/onboarding_email.riv", 0.533, -25.8, 13.5),
  password("assets/onboarding_password.riv", 0.5289, -36.2, -2.1),
  forgotPassword("assets/onboarding_forgot_password.riv", 0.5294, -28.5, -6.1),
  key("assets/onboarding_key.riv", 0.5325, -31, 6.7),
  recoveryKey("assets/onboarding_key.riv", 0.4714, -29.4, -4.6),
  pricing("assets/onboarding_pricing.riv", 0.535, -20.8, 7.9);

  const OnboardingIllustration(
    this.asset,
    this.scale,
    this.topOffset,
    this.centerOffset,
  );

  static const double artboardWidth = 500;
  static const double artboardHeight = 509;

  final String asset;
  final double scale;
  final double topOffset;
  final double centerOffset;

  double get width => artboardWidth * scale;
  double get height => artboardHeight * scale;
}

enum OnboardingTitleBarStyle { card, header }

class OnboardingPageScaffold extends StatefulWidget {
  const OnboardingPageScaffold({
    super.key,
    required this.title,
    required this.illustration,
    required this.body,
    this.actions = const [],
    this.headerHeight = defaultHeaderHeight,
    this.minimumKeyboardHeaderHeight = 0,
    this.showBackButton = true,
    this.titleBarStyle = OnboardingTitleBarStyle.card,
    this.headerTrailing,
    this.isBodyCentered = false,
    this.pinActions = false,
    this.showDeveloperSettingsTapArea = false,
  });

  static const double defaultHeaderHeight = 159;
  static const double compactHeaderHeight = 82;
  static const double planHeaderHeight = 148;
  static const double horizontalPadding = Spacing.xxl;

  final String title;
  final OnboardingIllustration illustration;
  final Widget body;
  final List<Widget> actions;
  final double headerHeight;
  final double minimumKeyboardHeaderHeight;
  final bool showBackButton;
  final OnboardingTitleBarStyle titleBarStyle;
  final Widget? headerTrailing;
  final bool isBodyCentered;

  // Only pin actions on pages that never show the keyboard.
  final bool pinActions;
  final bool showDeveloperSettingsTapArea;

  @override
  State<OnboardingPageScaffold> createState() => OnboardingPageScaffoldState();
}

class OnboardingPageScaffoldState extends State<OnboardingPageScaffold> {
  static const double _cardRadius = Radii.bottomSheet;
  static const double _cardBorderWidth = 1;
  static const double _titleBarHeight = 48;
  static const double _titleBarTopInset = 33;
  static const double _titleBarBottomInset = 17;
  static const double _inlineTitleTopInset = 36;
  static const double _inlineTitleBottomInset = 20;
  static const double _headerBarCenter = 33;
  static const double _headerBarLeftInset = 10;
  static const double _headerBarRightInset = 11;
  static const double _footerSpacing = Spacing.lg;
  static const double _footerInset = Spacing.xxl;

  rive.FileLoader? _fileLoader;
  late final Widget _illustrationWidget;
  rive.ViewModelInstance? _viewModel;
  String? _latestTrigger;
  Timer? _deferredTrigger;
  DateTime _entryCompletesAt = DateTime.now();
  DateTime? _illustrationPausedAt;
  ModalRoute<dynamic>? _route;
  ValueNotifier<bool>? _userGestureInProgress;
  final _titleKey = GlobalKey();
  final _bodyKey = GlobalKey();
  final _footerKey = GlobalKey();
  final _scrollKey = GlobalKey();
  EdgeInsets _viewInsets = EdgeInsets.zero;
  double? _contentHeight;
  double _measuredTitleHeight = _titleBarHeight;
  double _measuredFooterHeight = 0;
  double _footerSafeArea = 0;
  bool _measurementScheduled = false;

  bool get _isTransitioning =>
      (_route?.animation?.isAnimating ?? false) ||
      (_route?.secondaryAnimation?.isAnimating ?? false) ||
      (_userGestureInProgress?.value ?? false);

  double get _titleTopInset =>
      widget.titleBarStyle == OnboardingTitleBarStyle.card
      ? _titleBarTopInset
      : _inlineTitleTopInset;

  double get _keyboardProgress =>
      (_viewInsets.bottom / OnboardingPageScaffold.defaultHeaderHeight).clamp(
        0.0,
        1.0,
      );

  double get _titleBottomInset {
    final inset = widget.titleBarStyle == OnboardingTitleBarStyle.card
        ? _titleBarBottomInset
        : _inlineTitleBottomInset;
    return inset + (Spacing.sm - inset) * _keyboardProgress;
  }

  // Wait for entry to finish; interrupting it can freeze the pose.
  void trigger(String name) {
    _latestTrigger = name;
    if (_viewModel == null || _illustrationPausedAt != null) {
      return;
    }
    _deferredTrigger?.cancel();
    final remaining = _entryCompletesAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _trigger(name);
      return;
    }
    _deferredTrigger = Timer(remaining, () {
      if (mounted) _trigger(name);
    });
  }

  @override
  void initState() {
    super.initState();
    _fileLoader = _loadIllustration();
    _illustrationWidget = _buildIllustration();
    _scheduleContentMeasurement();
  }

  // Keep onboarding usable when the native Rive runtime is unavailable.
  rive.FileLoader? _loadIllustration() {
    try {
      return rive.FileLoader.fromAsset(
        widget.illustration.asset,
        riveFactory: rive.Factory.flutter,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _illustrationPausedAt ??= DateTime.now();
      _deferredTrigger?.cancel();
    } else if (_illustrationPausedAt != null) {
      _entryCompletesAt = _entryCompletesAt.add(
        DateTime.now().difference(_illustrationPausedAt!),
      );
      _illustrationPausedAt = null;
      final latest = _latestTrigger;
      if (latest != null) trigger(latest);
    }
    final route = ModalRoute.of(context);
    if (route != _route) {
      _route?.animation?.removeStatusListener(_onRouteAnimationStatus);
      _route?.secondaryAnimation?.removeStatusListener(
        _onSecondaryAnimationStatus,
      );
      _userGestureInProgress?.removeListener(_onUserGestureChanged);
      _route = route;
      _userGestureInProgress = route?.navigator?.userGestureInProgressNotifier;
      _userGestureInProgress?.addListener(_onUserGestureChanged);
      route?.animation?.addStatusListener(_onRouteAnimationStatus);
      route?.secondaryAnimation?.addStatusListener(_onSecondaryAnimationStatus);
    }
  }

  @override
  void dispose() {
    _route?.animation?.removeStatusListener(_onRouteAnimationStatus);
    _route?.secondaryAnimation?.removeStatusListener(
      _onSecondaryAnimationStatus,
    );
    _userGestureInProgress?.removeListener(_onUserGestureChanged);
    _deferredTrigger?.cancel();
    _viewModel = null;
    _fileLoader?.dispose();
    super.dispose();
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() {});
      _revealFocusedInput();
    }
  }

  void _onSecondaryAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed ||
        status == AnimationStatus.completed) {
      setState(() {});
      _revealFocusedInput();
    }
  }

  void _onUserGestureChanged() {
    if (!(_userGestureInProgress?.value ?? false)) {
      setState(() {});
      _revealFocusedInput();
    }
  }

  void _revealFocusedInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(_route?.isCurrent ?? true) || _isTransitioning) {
        return;
      }
      final focusContext = FocusManager.instance.primaryFocus?.context;
      if (focusContext == null || !focusContext.mounted) return;
      if (focusContext.findAncestorStateOfType<OnboardingPageScaffoldState>() !=
          this) {
        return;
      }
      final input = focusContext.findAncestorStateOfType<EditableTextState>();
      if (input == null || !input.textEditingValue.selection.isValid) return;
      if (input.widget.maxLines == 1) {
        unawaited(
          Scrollable.ensureVisible(
            focusContext,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ),
        );
      } else {
        input.bringIntoView(input.textEditingValue.selection.extent);
      }
    });
  }

  void _onLoaded(rive.RiveLoaded state) {
    _viewModel = state.viewModelInstance;
    final artboard = state.controller.artboard;
    for (var i = 0; i < artboard.animationCount(); i++) {
      final animation = artboard.animationAt(i);
      if (animation.name.toLowerCase() == "entry") {
        _entryDuration = Duration(
          milliseconds: (animation.duration * 1000).round(),
        );
      }
      animation.dispose();
    }
    _playEntry();
    final latest = _latestTrigger;
    if (latest != null) trigger(latest);
  }

  Duration _entryDuration = const Duration(seconds: 5);

  void _playEntry() {
    _entryCompletesAt = (_illustrationPausedAt ?? DateTime.now()).add(
      _entryDuration,
    );
    _trigger("entry");
  }

  void _trigger(String name) {
    _viewModel?.trigger(name)?.trigger();
  }

  void _onHeaderAnimationEnd() {
    if (_viewInsets.bottom > 0) _revealFocusedInput();
  }

  void _scheduleContentMeasurement() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final titleSize = _titleKey.currentContext?.size;
      final bodySize = _bodyKey.currentContext?.size;
      if (titleSize == null || bodySize == null) return;
      final footerSize = _footerKey.currentContext?.size;
      final contentHeight =
          _cardBorderWidth * 2 +
          titleSize.height +
          bodySize.height +
          (footerSize == null
              ? 0
              : footerSize.height - _footerSafeArea - _footerInset * 2);
      final footerHeight = footerSize?.height ?? 0;
      if (_contentHeight != null &&
          (_contentHeight! - contentHeight).abs() < precisionErrorTolerance &&
          (_measuredTitleHeight - titleSize.height).abs() <
              precisionErrorTolerance &&
          (_measuredFooterHeight - footerHeight).abs() <
              precisionErrorTolerance) {
        return;
      }
      setState(() {
        _contentHeight = contentHeight;
        _measuredTitleHeight = titleSize.height;
        _measuredFooterHeight = footerHeight;
      });
    });
  }

  Widget _measureContent(GlobalKey key, Widget child) {
    return SizeChangedLayoutNotifier(key: key, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final mediaQuery = MediaQuery.of(context);
    final keyboardChanged = _viewInsets != mediaQuery.viewInsets;
    _viewInsets = mediaQuery.viewInsets;
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;

    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleContentMeasurement();
        return false;
      },
      child: Scaffold(
        backgroundColor: colors.backgroundBase,
        resizeToAvoidBottomInset: true,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeaderHeight = _contentHeight == null
                ? widget.headerHeight
                : constraints.maxHeight -
                      mediaQuery.padding.top -
                      _contentHeight! -
                      _titleTopInset -
                      _titleBottomInset -
                      (widget.actions.isEmpty
                          ? 0
                          : _footerInset * 2 + mediaQuery.padding.bottom);
            final minimumHeaderHeight =
                widget.titleBarStyle == OnboardingTitleBarStyle.header
                ? math.min(
                    widget.headerHeight,
                    _headerBarCenter + _titleBarHeight / 2,
                  )
                : math.min(
                    widget.minimumKeyboardHeaderHeight,
                    math.max(
                      0,
                      constraints.maxHeight -
                          mediaQuery.padding.top -
                          _measuredFooterHeight -
                          _titleTopInset -
                          _titleBottomInset -
                          _measuredTitleHeight -
                          _titleBarHeight,
                    ),
                  );
            final keyboardHeaderHeight = availableHeaderHeight.clamp(
              minimumHeaderHeight,
              widget.headerHeight,
            );
            final headerHeight =
                mediaQuery.padding.top +
                (isKeyboardOpen ? keyboardHeaderHeight : widget.headerHeight);
            return Column(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: constraints.maxHeight),
                  child: AnimatedContainer(
                    duration:
                        _isTransitioning ||
                            _contentHeight == null ||
                            keyboardChanged ||
                            mediaQuery.disableAnimations
                        ? Duration.zero
                        : Motion.slow,
                    curve: Curves.easeOutCubic,
                    height: headerHeight,
                    onEnd: _onHeaderAnimationEnd,
                    child: _buildHeader(colors, mediaQuery),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => _buildCard(
                      context,
                      colors,
                      mediaQuery,
                      constraints.maxHeight,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(ColorTokens colors, MediaQueryData mediaQuery) {
    final illustration = widget.illustration;
    final compactIllustrationScale = mediaQuery.viewInsets.bottom > 0
        ? switch (illustration) {
            OnboardingIllustration.login ||
            OnboardingIllustration.password => 0.85,
            OnboardingIllustration.email => 0.65,
            OnboardingIllustration.key
                when widget.minimumKeyboardHeaderHeight > 0 =>
              0.65,
            _ => 0.0,
          }
        : 0.0;
    final hasHeaderBar = widget.titleBarStyle == OnboardingTitleBarStyle.header;
    final canPop = widget.showBackButton && (_route?.canPop ?? false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleHeaderHeight =
            constraints.maxHeight - mediaQuery.padding.top;
        final naturalScale = widget.headerHeight > 0
            ? (visibleHeaderHeight / widget.headerHeight).clamp(0.0, 1.0)
            : 0.0;
        final illustrationScale = compactIllustrationScale > 0
            ? math.max(
                naturalScale,
                (visibleHeaderHeight /
                        OnboardingPageScaffold.compactHeaderHeight *
                        compactIllustrationScale)
                    .clamp(0.0, compactIllustrationScale),
              )
            : naturalScale;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              bottom: -_cardRadius,
              child: _OnboardingBackdrop(color: colors.green),
            ),
            if (hasHeaderBar)
              Positioned(
                top:
                    mediaQuery.padding.top +
                    _headerBarCenter -
                    _titleBarHeight / 2,
                left: mediaQuery.padding.left + _headerBarLeftInset,
                right: mediaQuery.padding.right + _headerBarRightInset,
                height: _titleBarHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      width: _titleBarHeight,
                      child: canPop
                          ? _backButton(context, colors.specialWhite)
                          : null,
                    ),
                    SizedBox(
                      width: _titleBarHeight,
                      child: widget.headerTrailing,
                    ),
                  ],
                ),
              ),
            if (_fileLoader != null)
              Positioned(
                top:
                    mediaQuery.padding.top +
                    illustration.topOffset * illustrationScale +
                    (compactIllustrationScale > 0
                        ? (visibleHeaderHeight - widget.headerHeight) *
                              illustrationScale *
                              0.18
                        : 0),
                left: 0,
                right: 0,
                height: illustration.height,
                child: IgnorePointer(
                  child: Visibility(
                    visible: illustrationScale > 0,
                    maintainState: true,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Transform.translate(
                        offset: Offset(
                          illustration.centerOffset * illustrationScale,
                          0,
                        ),
                        child: Transform.scale(
                          scale: illustrationScale,
                          alignment: Alignment.topCenter,
                          child: _illustrationWidget,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildIllustration() {
    if (_fileLoader == null) return const SizedBox.shrink();
    return RepaintBoundary(
      child: SizedBox(
        width: widget.illustration.width,
        height: widget.illustration.height,
        child: rive.RiveWidgetBuilder(
          fileLoader: _fileLoader!,
          dataBind: rive.DataBind.auto(),
          onLoaded: _onLoaded,
          builder: (context, state) {
            if (state is rive.RiveLoaded) {
              return rive.RiveWidget(
                controller: state.controller,
                fit: rive.Fit.contain,
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _backButton(BuildContext context, Color color) {
    return ListenableBuilder(
      listenable: FocusManager.instance,
      builder: (context, child) {
        final focusContext = FocusManager.instance.primaryFocus?.context;
        final input = focusContext
            ?.findAncestorStateOfType<EditableTextState>();
        return TextFieldTapRegion(
          key: ValueKey(input?.widget.groupId),
          groupId: input?.widget.groupId ?? EditableText,
          child: child!,
        );
      },
      child: IconButtonComponent(
        variant: IconButtonComponentVariant.unfilled,
        size: _titleBarHeight,
        iconSize: IconSizes.medium,
        icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft02, color: color),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onTap: () => Navigator.of(context).maybePop(),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    ColorTokens colors,
    MediaQueryData mediaQuery,
    double availableHeight,
  ) {
    final hasCardTitleBar =
        widget.titleBarStyle == OnboardingTitleBarStyle.card;
    final canPop =
        hasCardTitleBar && widget.showBackButton && (_route?.canPop ?? false);
    final title = Text(
      widget.title,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyles.display2.copyWith(color: colors.textBase),
    );
    final titleContent = widget.showDeveloperSettingsTapArea
        ? DeveloperSettingsTapArea(
            behavior: HitTestBehavior.translucent,
            child: title,
          )
        : title;
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;
    final hasPinnedFooter =
        widget.actions.isNotEmpty && (widget.pinActions || isKeyboardOpen);
    final hasScrollingFooter = widget.actions.isNotEmpty && !hasPinnedFooter;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.backgroundBase,
        border: Border.all(color: colors.strokeDark, width: _cardBorderWidth),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(_cardRadius),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: FocusManager.instance,
              builder: (context, child) {
                final input = FocusManager.instance.primaryFocus?.context
                    ?.findAncestorStateOfType<EditableTextState>();
                return TextFieldTapRegion(
                  key: ValueKey(input?.widget.groupId),
                  groupId: input?.widget.groupId ?? EditableText,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                    child: child!,
                  ),
                );
              },
              child: CustomScrollView(
                key: _scrollKey,
                slivers: [
                  if (hasCardTitleBar)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        mediaQuery.padding.left +
                            OnboardingPageScaffold.horizontalPadding -
                            Spacing.md,
                        _titleTopInset,
                        mediaQuery.padding.right +
                            OnboardingPageScaffold.horizontalPadding -
                            Spacing.md,
                        _titleBottomInset,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _measureContent(
                          _titleKey,
                          Row(
                            children: [
                              SizedBox(
                                width: _titleBarHeight,
                                height: _titleBarHeight,
                                child: canPop
                                    ? _backButton(context, colors.textBase)
                                    : null,
                              ),
                              Expanded(child: titleContent),
                              const SizedBox(width: _titleBarHeight),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        mediaQuery.padding.left +
                            OnboardingPageScaffold.horizontalPadding,
                        _titleTopInset,
                        mediaQuery.padding.right +
                            OnboardingPageScaffold.horizontalPadding,
                        _titleBottomInset,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _measureContent(_titleKey, titleContent),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.only(
                      left:
                          mediaQuery.padding.left +
                          OnboardingPageScaffold.horizontalPadding,
                      right:
                          mediaQuery.padding.right +
                          OnboardingPageScaffold.horizontalPadding,
                    ),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        if (_contentHeight == null) {
                          _scheduleContentMeasurement();
                        }
                        final remaining =
                            constraints.viewportMainAxisExtent -
                            constraints.precedingScrollExtent;
                        return SliverToBoxAdapter(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: math.max(0, remaining),
                            ),
                            child: Column(
                              mainAxisAlignment: hasScrollingFooter
                                  ? MainAxisAlignment.spaceBetween
                                  : widget.isBodyCentered
                                  ? MainAxisAlignment.center
                                  : MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (widget.isBodyCentered)
                                  const SizedBox.shrink(),
                                _measureContent(_bodyKey, widget.body),
                                if (hasScrollingFooter)
                                  _buildFooter(mediaQuery, inline: true),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasPinnedFooter)
            if (isKeyboardOpen)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: availableHeight / 2),
                child: SingleChildScrollView(
                  child: _buildFooter(mediaQuery, inline: false),
                ),
              )
            else
              _buildFooter(mediaQuery, inline: false),
        ],
      ),
    );
  }

  Widget _buildFooter(MediaQueryData mediaQuery, {required bool inline}) {
    final horizontalInset = inline ? 0.0 : _footerInset;
    _footerSafeArea = mediaQuery.padding.bottom;
    return _measureContent(
      _footerKey,
      Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalInset + (inline ? 0 : mediaQuery.padding.left),
          _footerInset,
          horizontalInset + (inline ? 0 : mediaQuery.padding.right),
          _footerInset + _footerSafeArea,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.actions.length; i++) ...[
              if (i > 0) const SizedBox(height: _footerSpacing),
              widget.actions[i],
            ],
          ],
        ),
      ),
    );
  }
}

class OnboardingAccountPrompt extends StatelessWidget {
  const OnboardingAccountPrompt({
    super.key,
    required this.question,
    required this.actionLabel,
    required this.onTap,
  });

  final String question;
  final String actionLabel;
  final FutureOr<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Spacing.xs,
      children: [
        Text(
          question,
          textAlign: TextAlign.center,
          style: TextStyles.body.copyWith(color: colors.textLight),
        ),
        ButtonComponent(
          label: actionLabel,
          variant: ButtonComponentVariant.link,
          size: ButtonComponentSize.small,
          shouldSurfaceExecutionStates: false,
          onTap: onTap,
        ),
      ],
    );
  }
}

class _OnboardingBackdrop extends StatefulWidget {
  const _OnboardingBackdrop({required this.color});

  final Color color;

  @override
  State<_OnboardingBackdrop> createState() => _OnboardingBackdropState();
}

class _OnboardingBackdropState extends State<_OnboardingBackdrop> {
  static Future<PictureInfo?>? _texture;

  PictureInfo? _picture;

  @override
  void initState() {
    super.initState();
    _texture ??= _loadTexture();
    unawaited(
      _texture!.then((picture) {
        if (mounted && picture != null) setState(() => _picture = picture);
      }),
    );
  }

  static Future<PictureInfo?> _loadTexture() async {
    try {
      return await vg.loadPicture(
        const SvgAssetLoader("assets/onboarding_doodle.svg"),
        null,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRect(
        child: CustomPaint(
          isComplex: true,
          painter: _OnboardingBackdropPainter(
            color: widget.color,
            texture: _picture,
          ),
        ),
      ),
    );
  }
}

class _OnboardingBackdropPainter extends CustomPainter {
  const _OnboardingBackdropPainter({required this.color, this.texture});

  static const double textureWidth = 670;
  static const double textureHeight = 1006;
  static const double textureLeft = -90;
  static const double textureOpacity = 0.38 * 0.4;

  final Color color;
  final PictureInfo? texture;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final texture = this.texture;
    if (texture == null) return;
    const textureBounds = Rect.fromLTWH(
      textureLeft,
      0,
      textureWidth,
      textureHeight,
    );
    canvas.saveLayer(
      textureBounds.intersect(Offset.zero & size),
      Paint()
        ..blendMode = BlendMode.softLight
        ..color = Colors.white.withValues(alpha: textureOpacity),
    );
    canvas.drawRect(textureBounds, Paint()..color = Colors.black);
    canvas.translate(textureLeft, 0);
    canvas.scale(textureWidth / texture.size.width);
    canvas.drawPicture(texture.picture);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OnboardingBackdropPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.texture != texture;
  }
}
