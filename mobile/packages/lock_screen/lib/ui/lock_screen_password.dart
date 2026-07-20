import "package:ente_lock_screen/lock_screen_settings.dart";
import "package:ente_lock_screen/ui/lock_screen_confirm_password.dart";
import "package:ente_lock_screen/ui/lock_screen_options.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/android_text_input_autofocus.dart";
import "package:ente_ui/components/buttons/dynamic_fab.dart";
import "package:ente_ui/components/text_input_widget.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";

/// [isChangingLockScreenSettings] Authentication required for changing lock screen settings.
/// Set to true when the app requires the user to authenticate before allowing
/// changes to the lock screen settings.

/// [isAuthenticatingOnAppLaunch] Authentication required on app launch.
/// Set to true when the app requires the user to authenticate immediately upon opening.

/// [isAuthenticatingForInAppChange] Authentication required for in-app changes (e.g., email, password).
/// Set to true when the app requires the to authenticate for sensitive actions like email, password changes.

class LockScreenPassword extends StatefulWidget {
  const LockScreenPassword({
    super.key,
    this.isChangingLockScreenSettings = false,
    this.isAuthenticatingOnAppLaunch = false,
    this.isAuthenticatingForInAppChange = false,
    this.authPass,
  });

  final bool isChangingLockScreenSettings;
  final bool isAuthenticatingOnAppLaunch;
  final bool isAuthenticatingForInAppChange;
  final String? authPass;
  @override
  State<LockScreenPassword> createState() => _LockScreenPasswordState();
}

class _LockScreenPasswordState extends State<LockScreenPassword> {
  final _passwordController = TextEditingController(text: null);
  final _focusNode = FocusNode();
  final _isFormValid = ValueNotifier<bool>(false);
  final _submitNotifier = ValueNotifier(false);
  int invalidAttemptsCount = 0;

  final _lockscreenSetting = LockScreenSettings.instance;
  @override
  void initState() {
    super.initState();
    invalidAttemptsCount = _lockscreenSetting.getInvalidAttemptCount();
  }

  @override
  void dispose() {
    super.dispose();
    _submitNotifier.dispose();
    _focusNode.dispose();
    _isFormValid.dispose();
    _passwordController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorTheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isKeypadOpen = MediaQuery.viewInsetsOf(context).bottom > 100;

    FloatingActionButtonLocation? fabLocation() {
      if (isKeypadOpen) {
        return null;
      } else {
        return FloatingActionButtonLocation.centerFloat;
      }
    }

    return Scaffold(
      backgroundColor: colorTheme.backgroundBase,
      resizeToAvoidBottomInset: isKeypadOpen,
      appBar: AppBar(
        backgroundColor: colorTheme.backgroundBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop(false);
          },
          icon: Icon(Icons.arrow_back, color: colorTheme.textBase),
        ),
        centerTitle: true,
        title: SvgPicture.asset(
          LockScreenSettings.instance.appLogoAsset,
          height: LockScreenSettings.instance.appLogoHeight,
          colorFilter: ColorFilter.mode(colorTheme.primary700, BlendMode.srcIn),
        ),
      ),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _isFormValid,
        builder: (context, isFormValid, child) {
          return DynamicFAB(
            isKeypadOpen: isKeypadOpen,
            buttonText: context.strings.next,
            isFormValid: isFormValid,
            onPressedFunction: () async {
              _submitNotifier.value = !_submitNotifier.value;
            },
          );
        },
      ),
      floatingActionButtonLocation: fabLocation(),
      floatingActionButtonAnimator: NoScalingAnimation(),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Image.asset(
                  'assets/lock_screen_icon.png',
                  width: 129,
                  height: 95,
                ),
                const SizedBox(height: 24),
                Text(
                  widget.isChangingLockScreenSettings
                      ? context.strings.enterAppLockPassword
                      : context.strings.setNewPassword,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyBold,
                ),
                const Padding(padding: EdgeInsets.all(12)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AndroidTextInputAutofocus(
                    focusNode: _focusNode,
                    child: TextInputWidget(
                      hintText: context.strings.password,
                      autoFocus: true,
                      focusNode: _focusNode,
                      textCapitalization: TextCapitalization.none,
                      isPasswordInput: true,
                      shouldSurfaceExecutionStates: false,
                      onChange: (p0) {
                        _passwordController.text = p0;
                        _isFormValid.value =
                            _passwordController.text.isNotEmpty;
                      },
                      onSubmit: (p0) {
                        return _confirmPassword();
                      },
                      submitNotifier: _submitNotifier,
                    ),
                  ),
                ),
                const Padding(padding: EdgeInsets.all(12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmPasswordAuth(String inputtedPassword) async {
    final matched = _lockscreenSetting.useLegacyHashFallback
        ? await _lockscreenSetting.verifyWithLegacyFallback(
            text: inputtedPassword,
            storedHash: widget.authPass,
            storageKey: LockScreenSettings.password,
          )
        : await _lockscreenSetting.verify(
            text: inputtedPassword,
            storedHash: widget.authPass,
          );
    if (matched) {
      await _lockscreenSetting.setInvalidAttemptCount(0);

      if (mounted) {
        widget.isAuthenticatingOnAppLaunch ||
                widget.isAuthenticatingForInAppChange
            ? Navigator.of(context).pop(true)
            : Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => const LockScreenOptions(),
                ),
              );
      }
      return true;
    } else {
      if (widget.isAuthenticatingOnAppLaunch) {
        invalidAttemptsCount++;
        await _lockscreenSetting.setInvalidAttemptCount(invalidAttemptsCount);
        if (invalidAttemptsCount > 4 && mounted) {
          Navigator.of(context).pop(false);
        }
      }

      await HapticFeedback.vibrate();
      throw Exception("Incorrect password");
    }
  }

  Future<void> _confirmPassword() async {
    if (widget.isChangingLockScreenSettings) {
      await _confirmPasswordAuth(_passwordController.text);
      return;
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) =>
              LockScreenConfirmPassword(password: _passwordController.text),
        ),
      );
      if (mounted) {
        _passwordController.clear();
      }
    }
  }
}
