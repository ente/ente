import "package:ente_lock_screen/lock_screen_settings.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/android_text_input_autofocus.dart";
import "package:ente_ui/components/buttons/dynamic_fab.dart";
import "package:ente_ui/components/text_input_widget.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";

class LockScreenConfirmPassword extends StatefulWidget {
  const LockScreenConfirmPassword({super.key, required this.password});
  final String password;

  @override
  State<LockScreenConfirmPassword> createState() =>
      _LockScreenConfirmPasswordState();
}

class _LockScreenConfirmPasswordState extends State<LockScreenConfirmPassword> {
  final _confirmPasswordController = TextEditingController(text: null);
  final LockScreenSettings _lockscreenSetting = LockScreenSettings.instance;
  final _focusNode = FocusNode();
  final _isFormValid = ValueNotifier<bool>(false);
  final _submitNotifier = ValueNotifier(false);

  @override
  void dispose() {
    _submitNotifier.dispose();
    _focusNode.dispose();
    _isFormValid.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _confirmPasswordMatch() async {
    if (widget.password == _confirmPasswordController.text) {
      await _lockscreenSetting.setPassword(_confirmPasswordController.text);

      if (mounted) {
        Navigator.of(context).pop(true);
        Navigator.of(context).pop(true);
      }
      return;
    }
    await HapticFeedback.vibrate();
    throw Exception("Incorrect password");
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
            Navigator.of(context).pop();
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
            buttonText: context.strings.confirm,
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
                  context.strings.reEnterPassword,
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
                        _confirmPasswordController.text = p0;
                        _isFormValid.value =
                            _confirmPasswordController.text.isNotEmpty;
                      },
                      onSubmit: (p0) {
                        return _confirmPasswordMatch();
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
}
