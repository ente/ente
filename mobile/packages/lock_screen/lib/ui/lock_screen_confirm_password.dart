import "package:ente_components/ente_components.dart";
import "package:ente_lock_screen/lock_screen_settings.dart";
import "package:ente_lock_screen/ui/lock_screen_submit_fab.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/android_text_input_autofocus.dart";
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
    if (_confirmPasswordController.text.isEmpty) return;

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
    final colorTheme = context.componentColors;

    return Scaffold(
      backgroundColor: colorTheme.backgroundBase,
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
          colorFilter: ColorFilter.mode(colorTheme.primary, BlendMode.srcIn),
        ),
      ),
      floatingActionButton: LockScreenSubmitFab(
        label: context.strings.confirm,
        isFormValid: _isFormValid,
        onSubmit: () => _submitNotifier.value = !_submitNotifier.value,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
                  style: TextStyles.bodyBold,
                ),
                const Padding(padding: EdgeInsets.all(12)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AndroidTextInputAutofocus(
                    focusNode: _focusNode,
                    child: TextInputComponent(
                      controller: _confirmPasswordController,
                      hintText: context.strings.password,
                      autofocus: true,
                      focusNode: _focusNode,
                      textCapitalization: TextCapitalization.none,
                      textInputAction: TextInputAction.done,
                      isPasswordInput: true,
                      onChanged: (p0) {
                        _isFormValid.value = p0.isNotEmpty;
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
