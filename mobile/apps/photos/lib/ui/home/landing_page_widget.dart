import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/pages/language_selector_page.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:photos/app.dart";
import 'package:photos/core/configuration.dart';
import "package:photos/locale.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import 'package:photos/ui/account/email_entry_page.dart';
import 'package:photos/ui/account/login_page.dart';
import 'package:photos/ui/account/password_entry_page.dart';
import 'package:photos/ui/account/password_reentry_page.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/dialog_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import 'package:photos/ui/payment/subscription.dart';
import "package:photos/ui/settings/developer_settings_tap_area.dart";
import "package:photos/ui/settings/developer_settings_widget.dart";
import "package:rive/rive.dart" as rive;

class LandingPageWidget extends StatefulWidget {
  const LandingPageWidget({required this.onStartWithoutAccount, super.key});
  final VoidCallback onStartWithoutAccount;

  @override
  State<LandingPageWidget> createState() => _LandingPageWidgetState();
}

class _LandingPageWidgetState extends State<LandingPageWidget> {
  late final rive.FileLoader _onboardingAnimationLoader;

  @override
  void initState() {
    super.initState();
    _onboardingAnimationLoader = rive.FileLoader.fromAsset(
      "assets/onboarding.riv",
      riveFactory: rive.Factory.flutter,
    );
    Future(_showAutoLogoutDialogIfRequired);
  }

  @override
  void dispose() {
    _onboardingAnimationLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lightComponentTheme = ComponentTheme.lightTheme(
      app: ComponentApp.photos,
    );
    return Theme(
      data: lightComponentTheme,
      child: Builder(
        builder: (context) {
          final colorScheme = getEnteColorScheme(context);
          return Scaffold(
            backgroundColor: colorScheme.greenBase,
            body: SafeArea(
              child: DeveloperSettingsTapArea(
                onSettingsChanged: () {
                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (kDebugMode) _buildDebugLanguageButton(),

                                    _buildOnboardingAnimation(),

                                    Text(
                                      context.strings.onboardingTitle,
                                      textAlign: TextAlign.center,
                                      textScaler: TextScaler.noScaling,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontFamily: TextStyles.outfitFontFamily,
                                        package: TextStyles.fontPackage,
                                        fontSize: 28,
                                        height: 30 / 28,
                                        color: Colors.white,
                                      ),
                                    ),

                                    const SizedBox(height: 24),

                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 32,
                                      ),
                                      child: Text(
                                        context.strings.onboardingOrganizeDesc,
                                        textAlign: TextAlign.center,
                                        style: TextStyles.body.copyWith(
                                          color: colorScheme.greenLight,
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 32),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: ButtonComponent(
                          variant: ButtonComponentVariant.neutral,
                          density: ButtonComponentDensity.compact,
                          label: context.strings.createMyAccount,
                          onTap: _navigateToSignUpPage,
                          shouldSurfaceExecutionStates: false,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: _navigateToSignInPage,
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Text(
                              context.strings.logInLabel,
                              style: TextStyles.body.copyWith(
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (localSettings.showLocalGalleryModeOption) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: _navigateWithoutAccount,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: Text(
                                context.strings.continueWithoutAccount,
                                style: TextStyles.bodyLink.copyWith(
                                  color: Colors.white,
                                  decorationColor: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const DeveloperSettingsWidget(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOnboardingAnimation() {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.325,
      ),
      child: rive.RiveWidgetBuilder(
        fileLoader: _onboardingAnimationLoader,
        builder: (BuildContext context, rive.RiveState state) {
          if (state is rive.RiveLoaded) {
            return rive.RiveWidget(
              controller: state.controller,
              fit: rive.Fit.contain,
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildDebugLanguageButton() {
    return GestureDetector(
      child: const Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.only(right: 16),
          child: Text("Lang", style: TextStyle(color: Colors.black54)),
        ),
      ),
      onTap: () async {
        final locale = (await getLocale())!;
        if (!mounted) return;
        unawaited(
          routeToPage(
            context,
            LanguageSelectorPage(appSupportedLocales, (locale) async {
              await setLocale(locale);
              if (!mounted) return;
              EnteApp.setLocale(context, locale);
              unawaited(StringsLocalizations.delegate.load(locale));
            }, locale),
          ).then((value) {
            if (!mounted) return;
            setState(() {});
          }),
        );
      },
    );
  }

  void _navigateWithoutAccount() {
    widget.onStartWithoutAccount();
  }

  Future<void> _navigateToSignUpPage() async {
    updateService.hideChangeLog().ignore();
    Widget page;
    if (Configuration.instance.getEncryptedToken() == null) {
      page = const EmailEntryPage();
    } else {
      if (Configuration.instance.getKeyAttributes() == null) {
        page = const PasswordEntryPage(mode: PasswordEntryMode.set);
      } else if (Configuration.instance.getKey() == null) {
        page = const PasswordReentryPage();
      } else {
        page = getSubscriptionPage(isOnBoarding: true);
      }
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return page;
          },
        ),
      ),
    );
  }

  void _navigateToSignInPage() {
    updateService.hideChangeLog().ignore();
    Widget page;
    if (Configuration.instance.getEncryptedToken() == null) {
      page = const LoginPage();
    } else {
      if (Configuration.instance.getKeyAttributes() == null) {
        page = const PasswordEntryPage(mode: PasswordEntryMode.set);
      } else if (Configuration.instance.getKey() == null) {
        page = const PasswordReentryPage();
      } else {
        page = getSubscriptionPage(isOnBoarding: true);
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

  Future<void> _showAutoLogoutDialogIfRequired() async {
    final bool autoLogout = Configuration.instance.showAutoLogoutDialog();
    if (autoLogout) {
      final result = await showDialogWidget(
        context: context,
        title: context.strings.pleaseLoginAgain,
        body: context.strings.autoLogoutMessage,
        buttons: [
          ButtonWidget(
            buttonType: ButtonType.neutral,
            buttonAction: ButtonAction.first,
            labelText: context.strings.ok,
            isInAlert: true,
          ),
        ],
      );
      Configuration.instance.clearAutoLogoutFlag().ignore();
      if (result?.action != null && result!.action == ButtonAction.first) {
        _navigateToSignInPage();
      }
    }
  }
}
