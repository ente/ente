import 'dart:async';
import 'dart:io';

import 'package:dots_indicator/dots_indicator.dart';
import 'package:ente_accounts/pages/email_entry_page.dart';
import 'package:ente_accounts/pages/login_page.dart';
import 'package:ente_accounts/pages/password_entry_page.dart';
import 'package:ente_accounts/pages/password_reentry_page.dart';
import 'package:ente_auth/app/view/app.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/events/trigger_logout_event.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/locale.dart';
import 'package:ente_auth/theme/colors.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/account/logout_dialog.dart';
import 'package:ente_auth/ui/common/gradient_button.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/models/button_result.dart';
import 'package:ente_auth/ui/home/widgets/rounded_action_buttons.dart';
import 'package:ente_auth/ui/home_page.dart';
import 'package:ente_auth/ui/settings/developer_settings_widget.dart';
import 'package:ente_auth/ui/settings/language_picker.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/navigation_util.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_ui/components/alert_bottom_sheet.dart';
import 'package:ente_ui/pages/developer_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:local_auth/local_auth.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const kDeveloperModeTapCountThreshold = 7;
  static const _featureCount = 3;
  static const _autoScrollInterval = Duration(seconds: 4);

  late StreamSubscription<TriggerLogoutEvent> _triggerLogoutEvent;
  late final PageController _pageController;
  Timer? _autoScrollTimer;

  int _developerModeTapCount = 0;
  int _activeDotIndex = 0;
  int _currentPage = 0;
  bool _autoScrollDisabled = false;

  @override
  void initState() {
    const initialPage = _featureCount * 1000;
    _pageController = PageController(initialPage: initialPage);
    _pageController.addListener(_handlePageControllerScroll);
    _currentPage = initialPage;
    _activeDotIndex = _currentPage % _featureCount;
    _triggerLogoutEvent = Bus.instance.on<TriggerLogoutEvent>().listen((
      event,
    ) async {
      if (!mounted) return;
      await autoLogoutAlert(context);
    });
    _startAutoScroll();
    super.initState();
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _pageController.removeListener(_handlePageControllerScroll);
    _pageController.dispose();
    _triggerLogoutEvent.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("Building OnboardingPage");
    final l10n = context.l10n;
    final textTheme = getEnteTextTheme(context);

    return Scaffold(
      backgroundColor: accentColor,
      appBar: AppBar(
        leading: const SizedBox(),
        title: SvgPicture.asset("assets/svg/app-logo.svg"),
        backgroundColor: accentColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        actions: 1 != 1
            ? [
                GestureDetector(
                  onTap: () async {
                    final locale = (await getLocale())!;
                    if (!context.mounted) return;
                    unawaited(
                      routeToPage(
                        context,
                        LanguageSelectorPage(appSupportedLocales, (
                          locale,
                        ) async {
                          await setLocale(locale);
                          if (!context.mounted) return;
                          App.setLocale(context, locale);
                        }, locale),
                      ).then((value) {
                        setState(() {});
                      }),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      "Lang(i)",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ]
            : null,
      ),
      body: GestureDetector(
        onTap: () async => _handleDeveloperTap(context),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    const SizedBox(height: 28),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildFeatureSlider(context),
                          const SizedBox(height: 12),
                          _buildDotsIndicator(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 580),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Row(
                          children: [
                            Expanded(
                              child: RoundedButton(
                                label: l10n.signUp,
                                onPressed: _navigateToSignUpPage,
                                type: RoundedButtonType.secondaryInverse,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: RoundedButton(
                                label: l10n.logInLabel,
                                onPressed: _navigateToSignInPage,
                                type: RoundedButtonType.primaryInverse,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _optForOfflineMode,
                      child: Text(
                        l10n.useOffline,
                        style: textTheme.bodyBold.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const DeveloperSettingsWidget(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleDeveloperTap(BuildContext context) async {
    _developerModeTapCount++;
    if (_developerModeTapCount >= kDeveloperModeTapCountThreshold) {
      _developerModeTapCount = 0;
      await showAlertBottomSheet(
        context,
        title: context.l10n.developerSettings,
        message: context.l10n.developerSettingsWarning,
        assetPath: 'assets/warning-grey.png',
        isDismissible: false,
        showCloseButton: false,
        buttons: [
          GradientButton(
            text: context.l10n.yes,
            onTap: () async {
              Navigator.of(context).pop();
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (BuildContext context) {
                    return DeveloperSettingsPage(
                      getCurrentEndpoint: () =>
                          Configuration.instance.getHttpEndpoint(),
                      setEndpoint: (url) async =>
                          Configuration.instance.setHttpEndpoint(url),
                    );
                  },
                ),
              );
              if (mounted) {
                setState(() {});
              }
            },
          ),
        ],
      );
    }
  }

  Future<void> _optForOfflineMode() async {
    bool canCheckBio =
        Platform.isMacOS ||
        Platform.isLinux ||
        Platform.isWindows ||
        await LocalAuthentication().canCheckBiometrics;
    if (!canCheckBio) {
      if (!mounted) return;
      showToast(
        context,
        "Sorry, biometric authentication is not supported on this device.",
      );
      return;
    }
    final bool hasOptedBefore = Configuration.instance.hasOptedForOfflineMode();
    ButtonResult? result;
    if (!hasOptedBefore) {
      if (!mounted) return;
      result = await showChoiceActionSheet(
        context,
        title: context.l10n.warning,
        body: context.l10n.offlineModeWarning,
        secondButtonLabel: context.l10n.cancel,
        firstButtonLabel: context.l10n.ok,
      );
    }
    if (hasOptedBefore || result?.action == ButtonAction.first) {
      if (!context.mounted) return;
      await Configuration.instance.optForOfflineMode();
      if (!mounted) return;
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const HomePage();
            },
          ),
        ),
      );
    }
  }

  void _startAutoScroll() {
    if (_autoScrollDisabled) {
      return;
    }
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(_autoScrollInterval, (_) {
      if (!_pageController.hasClients) {
        return;
      }
      final nextPage = _currentPage + 1;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _handlePageControllerScroll() {
    if (!_pageController.hasClients) {
      return;
    }

    // Check if user is manually scrolling
    // userScrollDirection is idle during programmatic scrolling (animateToPage)
    // but becomes forward/reverse when user manually drags
    if (_pageController.position.userScrollDirection != ScrollDirection.idle) {
      _autoScrollDisabled = true;
      _stopAutoScroll();
    }
  }

  void _animateToFeature(int index) {
    if (!_pageController.hasClients) {
      return;
    }
    final base = _currentPage - (_currentPage % _featureCount);
    final targetPage = base + index;
    if (targetPage == _currentPage) {
      return;
    }
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildFeatureSlider(BuildContext context) {
    final l10n = context.l10n;
    final features = [
      ("assets/onboarding-1.png", l10n.featureBackupCodes),
      ("assets/onboarding-2.png", l10n.featureSearchEtc),
      ("assets/onboarding-3.png", l10n.featureOpenSource),
    ];
    assert(features.length == _featureCount);

    final screenWidth = MediaQuery.of(context).size.width;
    final shouldApplyFade = screenWidth >= 800;

    final pageView = SizedBox(
      height: 320,
      child: PageView.builder(
        controller: _pageController,
        itemBuilder: (context, index) {
          final feature = features[index % features.length];
          return _FeatureItemWidget(assetPath: feature.$1, title: feature.$2);
        },
        onPageChanged: (index) {
          setState(() {
            _currentPage = index;
            _activeDotIndex = index % _featureCount;
          });
          _startAutoScroll();
        },
      ),
    );

    if (!shouldApplyFade) {
      return pageView;
    }

    const fadeWidth = 400.0;
    final leftFadeEnd = fadeWidth / screenWidth;
    final rightFadeStart = (screenWidth - fadeWidth) / screenWidth;

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, leftFadeEnd, rightFadeStart, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: pageView,
    );
  }

  Widget _buildDotsIndicator() {
    return DotsIndicator(
      dotsCount: _featureCount,
      position: _activeDotIndex.toDouble(),
      decorator: DotsDecorator(
        activeColor: Colors.white,
        color: Colors.white.withValues(alpha: 0.32),
        activeShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        size: const Size(10, 10),
        activeSize: const Size(20, 10),
        spacing: const EdgeInsets.all(6),
      ),
      animate: true,
      animationDuration: const Duration(milliseconds: 300),
      onTap: (index) {
        _autoScrollDisabled = true;
        _stopAutoScroll();
        _animateToFeature(index);
      },
    );
  }

  void _navigateToSignUpPage() {
    Widget page;
    if (Configuration.instance.getEncryptedToken() == null) {
      page = EmailEntryPage(Configuration.instance);
    } else {
      // No key
      if (Configuration.instance.getKeyAttributes() == null) {
        // Never had a key
        page = PasswordEntryPage(
          Configuration.instance,
          PasswordEntryMode.set,
          const HomePage(),
        );
      } else if (Configuration.instance.getKey() == null) {
        // Yet to decrypt the key
        page = PasswordReentryPage(Configuration.instance, const HomePage());
      } else {
        // All is well, user just has not subscribed
        page = const HomePage();
      }
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return page;
        },
      ),
    );
  }

  void _navigateToSignInPage() {
    Widget page;
    if (Configuration.instance.getEncryptedToken() == null) {
      page = LoginPage(Configuration.instance);
    } else {
      // No key
      if (Configuration.instance.getKeyAttributes() == null) {
        // Never had a key
        page = PasswordEntryPage(
          Configuration.instance,
          PasswordEntryMode.set,
          const HomePage(),
        );
      } else if (Configuration.instance.getKey() == null) {
        // Yet to decrypt the key
        page = PasswordReentryPage(Configuration.instance, const HomePage());
      } else {
        // All is well, user just has not subscribed
        // page = getSubscriptionPage(isOnBoarding: true);
        page = const HomePage();
      }
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return page;
        },
      ),
    );
  }
}

class _FeatureItemWidget extends StatelessWidget {
  const _FeatureItemWidget({required this.assetPath, required this.title});

  final String assetPath;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Image.asset(assetPath, height: 188),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            title,
            style: getEnteTextTheme(
              context,
            ).largeBold.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
