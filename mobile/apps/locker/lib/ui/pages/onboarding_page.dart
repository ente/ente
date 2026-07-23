import 'dart:async';

import 'package:dots_indicator/dots_indicator.dart';
import 'package:ente_accounts/pages/email_entry_page.dart';
import 'package:ente_accounts/pages/login_page.dart';
import 'package:ente_accounts/pages/password_entry_page.dart';
import 'package:ente_accounts/pages/password_reentry_page.dart';
import 'package:ente_components/ente_components.dart';
import "package:ente_ui/pages/developer_settings_page.dart";
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import "package:flutter_svg/flutter_svg.dart";
import 'package:locker/l10n/l10n.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/ui/pages/home_page.dart';
import "package:locker/utils/bottom_sheet_illustration.dart";

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const kDeveloperModeTapCountThreshold = 7;
  static const _featureCount = 3;
  static const _autoScrollInterval = Duration(seconds: 4);

  late final PageController _pageController;
  Timer? _autoScrollTimer;

  int _developerModeTapCount = 0;
  int _activeDotIndex = 0;
  int _currentPage = 0;
  bool _autoScrollDisabled = false;

  @override
  void initState() {
    super.initState();
    const initialPage = _featureCount * 1000;
    _pageController = PageController(initialPage: initialPage);
    _pageController.addListener(_handlePageControllerScroll);
    _currentPage = initialPage;
    _activeDotIndex = _currentPage % _featureCount;
    _startAutoScroll();
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _pageController.removeListener(_handlePageControllerScroll);
    _pageController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final lightComponentTheme = ComponentTheme.lightTheme(
      app: ComponentApp.locker,
    );
    debugPrint("Building OnboardingPage");
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: colors.primary,
      appBar: AppBar(
        leading: const SizedBox(),
        title: SvgPicture.asset("assets/svg/app-logo.svg"),
        backgroundColor: colors.primary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () async {
            _developerModeTapCount++;
            if (_developerModeTapCount >= kDeveloperModeTapCountThreshold) {
              _developerModeTapCount = 0;
              await showBottomSheetComponent(
                context: context,
                builder: (_) => BottomSheetComponent(
                  title: l10n.developerSettings,
                  message: l10n.developerSettingsWarning,
                  illustration: LockerBottomSheetIllustration.warningGrey,
                  actions: [
                    ButtonComponent(
                      label: l10n.yes,
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
                        setState(() {});
                      },
                    ),
                  ],
                ),
              );
            }
          },
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    const SizedBox(height: 28),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _getFeatureSlider(context),
                          const SizedBox(height: 12),
                          DotsIndicator(
                            dotsCount: _featureCount,
                            position: _activeDotIndex.toDouble(),
                            animate: true,
                            animationDuration: const Duration(
                              milliseconds: 300,
                            ),
                            decorator: DotsDecorator(
                              activeColor: colors.specialWhite,
                              color: colors.specialWhite.withValues(
                                alpha: 0.32,
                              ),
                              activeShape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              size: const Size(10, 10),
                              activeSize: const Size(20, 10),
                              spacing: const EdgeInsets.all(6),
                            ),
                            onTap: _animateToFeature,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Theme(
                        data: lightComponentTheme,
                        child: Column(
                          children: [
                            ButtonComponent(
                              variant: ButtonComponentVariant.neutral,
                              label: l10n.createAnEnteAccount,
                              onTap: _navigateToSignUpPage,
                              shouldSurfaceExecutionStates: false,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _navigateToSignInPage,
                      child: Text(
                        l10n.loginToExistingAccount,
                        style: TextStyles.body.copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: colors.specialWhite,
                          color: colors.specialWhite,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getFeatureSlider(BuildContext context) {
    final l10n = context.l10n;
    final features = [
      ("assets/onboarding_lock.png", l10n.featureSaveImportant),
      ("assets/onboarding_file.png", l10n.featurePassAutomatically),
      ("assets/onboarding_share.png", l10n.featureShareAnytime),
    ];

    return SizedBox(
      height: 320,
      child: PageView.builder(
        controller: _pageController,
        itemBuilder: (context, index) {
          final feature = features[index % features.length];
          return FeatureItemWidget(feature.$1, feature.$2);
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
        // All is well
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

class FeatureItemWidget extends StatelessWidget {
  final String assetPath;
  final String featureTitleFirstLine;

  const FeatureItemWidget(
    this.assetPath,
    this.featureTitleFirstLine, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Image.asset(assetPath, height: 200),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                featureTitleFirstLine,
                style: TextStyles.large.copyWith(color: colors.specialWhite),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
