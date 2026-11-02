import 'package:dio/dio.dart';
import "package:ente_components/ente_components.dart";
import 'package:ente_crypto/ente_crypto.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/notification_event.dart';
import "package:photos/service_locator.dart";
import 'package:photos/services/account/user_service.dart';
import 'package:photos/src/rust/third_party/ente_frb_lib/recovery.dart'
    as recovery;
import 'package:photos/ui/account/recovery_key_page.dart';
import "package:photos/ui/components/alert_bottom_sheet.dart";
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/utils/dialog_util.dart';

class VerifyRecoveryPage extends StatefulWidget {
  const VerifyRecoveryPage({super.key});

  @override
  State<VerifyRecoveryPage> createState() => _VerifyRecoveryPageState();
}

class _VerifyRecoveryPageState extends State<VerifyRecoveryPage> {
  final _recoveryKey = TextEditingController();
  final Logger _logger = Logger((_VerifyRecoveryPageState).toString());

  @override
  void dispose() {
    _recoveryKey.dispose();
    super.dispose();
  }

  void _verifyRecoveryKey() async {
    final dialog = createProgressDialog(
      context,
      context.strings.verifyingRecoveryKey,
    );
    await dialog.show();
    try {
      final String inputKey = _recoveryKey.text.trim();
      if (!mounted) return;
      final String recoveryKey = CryptoUtil.bin2hex(
        await UserService.instance.getOrCreateRecoveryKey(context),
      );
      final String recoveryKeyWords = recovery.recoveryKeyToMnemonic(
        recoveryKeyHex: recoveryKey,
      );
      if (inputKey == recoveryKey || inputKey == recoveryKeyWords) {
        try {
          await flagService.setRecoveryKeyVerified(true);
        } catch (e) {
          await dialog.hide();
          if (e is DioException && e.type == DioExceptionType.connectionError) {
            if (!mounted) return;
            await showAlertBottomSheet(
              context,
              title: context.strings.noInternetConnection,
              message:
                  context.strings.pleaseCheckYourInternetConnectionAndTryAgain,
              assetPath: 'assets/warning-grey.png',
            );
          } else {
            if (!mounted) return;
            await showGenericErrorBottomSheet(context: context, error: e);
          }
          return;
        }
        Bus.instance.fire(NotificationEvent());
        await dialog.hide();
        if (!mounted) return;
        await showAlertBottomSheet(
          context,
          title: context.strings.recoveryKeyVerified,
          message: context.strings.recoveryKeySuccessBody,
          assetPath: 'assets/warning-grey.png',
        );
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        throw Exception("recovery key didn't match");
      }
    } catch (e, s) {
      _logger.severe("failed to verify recovery key", e, s);
      await dialog.hide();
      if (!mounted) return;
      final String errMessage = context.strings.invalidRecoveryKey;
      if (!mounted) return;
      final result = await showChoiceDialog(
        context,
        title: context.strings.invalidKey,
        body: errMessage,
        firstButtonLabel: context.strings.tryAgain,
        secondButtonLabel: context.strings.viewRecoveryKey,
        secondButtonAction: ButtonAction.second,
      );
      if (result?.action == ButtonAction.second) {
        await _onViewRecoveryKeyClick();
      }
    }
  }

  Future<void> _onViewRecoveryKeyClick() async {
    final hasAuthenticated = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          "Please authenticate to view your recovery key",
        );
    if (hasAuthenticated) {
      String recoveryKey;
      try {
        if (!mounted) return;
        recoveryKey = CryptoUtil.bin2hex(
          await UserService.instance.getOrCreateRecoveryKey(context),
        );
        if (!mounted) return;
        // ignore: unawaited_futures
        routeToPage(
          context,
          RecoveryKeyPage(
            recoveryKey,
            context.strings.ok,
            isOnboarding: false,
            onDone: () {
              Navigator.of(context).pop();
            },
          ),
        );
      } catch (e) {
        if (!mounted) return;
        await showGenericErrorBottomSheet(context: context, error: e);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colors.backgroundBase,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: colors.iconColor,
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth,
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          context.strings.confirmRecoveryKey,
                          style: TextStyles.h1.copyWith(color: colors.textBase),
                          textAlign: TextAlign.left,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        context.strings.recoveryKeyVerifyReason,
                        style: TextStyles.mini.copyWith(
                          color: colors.textLight,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextInputComponent(
                        controller: _recoveryKey,
                        hintText: context.strings.enterYourRecoveryKey,
                        autocorrect: false,
                        keyboardType: TextInputType.multiline,
                        minLines: 4,
                        maxLines: null,
                        onChanged: (_) {
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          alignment: Alignment.bottomCenter,
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(0, 12, 0, 40),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ButtonComponent(
                                label: context.strings.confirm,
                                onTap: _verifyRecoveryKey,
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
