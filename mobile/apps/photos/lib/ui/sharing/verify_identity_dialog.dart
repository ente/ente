import "dart:convert";

import 'package:bip39/bip39.dart' as bip39;
import "package:crypto/crypto.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/base_bottom_sheet.dart";
import 'package:photos/ui/components/buttons/button_widget.dart';
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/utils/share_util.dart";

Future<void> showVerifyIdentitySheet(
  BuildContext context, {
  required bool self,
  String email = '',
  String? title,
}) {
  return showBaseBottomSheet<void>(
    context,
    title: title ?? AppLocalizations.of(context).verify,
    headerSpacing: 20,
    child: _VerifyIdentitySheetContent(self: self, email: email),
  );
}

class _VerifyIdentitySheetContent extends StatefulWidget {
  // email id of the user who's verification ID is being displayed for
  // verification
  final String email;

  // self is true when the user is viewing their own verification ID
  final bool self;

  _VerifyIdentitySheetContent({required this.self, this.email = ''}) {
    if (!self && email.isEmpty) {
      throw ArgumentError("email cannot be empty when self is false");
    }
  }

  @override
  State<_VerifyIdentitySheetContent> createState() =>
      _VerifyIdentitySheetContentState();
}

class _VerifyIdentitySheetContentState
    extends State<_VerifyIdentitySheetContent> {
  @override
  Widget build(BuildContext context) {
    final String subTitle = widget.self
        ? AppLocalizations.of(context).thisIsYourVerificationId
        : AppLocalizations.of(
            context,
          ).thisIsPersonVerificationId(email: widget.email);
    final String bottomText = widget.self
        ? AppLocalizations.of(
            context,
          ).someoneSharingAlbumsWithYouShouldSeeTheSameId
        : AppLocalizations.of(context).howToViewShareeVerificationID;

    final colorScheme = getEnteColorScheme(context);
    final textStyle = getEnteTextTheme(context);

    return FutureBuilder<String>(
      future: _getPublicKey(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final publicKey = snapshot.data!;
          if (publicKey.isEmpty) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(
                    context,
                  ).emailNoEnteAccount(email: widget.email),
                  style: textStyle.small.copyWith(color: colorScheme.textMuted),
                ),
                const SizedBox(height: 20),
                ButtonWidget(
                  buttonType: ButtonType.neutral,
                  icon: Icons.adaptive.share,
                  labelText: AppLocalizations.of(context).sendInvite,
                  onTap: () async {
                    await shareText(
                      AppLocalizations.of(context).shareTextRecommendUsingEnte,
                    );
                  },
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                subTitle,
                style: textStyle.small.copyWith(color: colorScheme.textMuted),
              ),
              const SizedBox(height: 20),
              _verificationIDSheetWidget(context, publicKey),
              const SizedBox(height: 20),
              Text(
                bottomText,
                style: textStyle.small.copyWith(color: colorScheme.textMuted),
              ),
            ],
          );
        } else if (snapshot.hasError) {
          Logger(
            "VerificationID",
          ).severe("failed to end userID", snapshot.error);
          return Text(
            AppLocalizations.of(context).somethingWentWrong,
            style: textStyle.bodyMuted,
          );
        }
        return const SizedBox(height: 200, child: EnteLoadingWidget());
      },
    );
  }

  Future<String> _getPublicKey() async {
    if (widget.self) {
      return Configuration.instance.getKeyAttributes()!.publicKey;
    }
    final String? userPublicKey = await UserService.instance.getPublicKey(
      widget.email,
    );
    if (userPublicKey == null) {
      // user not found
      return "";
    }
    return userPublicKey;
  }

  Widget _verificationIDSheetWidget(BuildContext context, String publicKey) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final String verificationID = _generateVerificationID(publicKey);

    return GestureDetector(
      onTap: () => _shareVerificationID(context, verificationID),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: colorScheme.primary700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        width: double.infinity,
        child: Text(
          verificationID,
          style: textTheme.body.copyWith(
            color: Colors.white,
            fontFamily: 'monospace',
            letterSpacing: 0.5,
            height: 1.5,
          ),
          textAlign: TextAlign.justify,
        ),
      ),
    );
  }

  Future<void> _shareVerificationID(
    BuildContext context,
    String verificationID,
  ) async {
    if (verificationID.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: verificationID));
    if (!context.mounted) return;
    await shareText(
      widget.self
          ? AppLocalizations.of(
              context,
            ).shareMyVerificationID(verificationID: verificationID)
          : AppLocalizations.of(context).shareTextConfirmOthersVerificationID(
              verificationID: verificationID,
            ),
    );
  }

  String _generateVerificationID(String publicKey) {
    final inputBytes = base64.decode(publicKey);
    final shaValue = sha256.convert(inputBytes);
    return bip39.generateMnemonic(
      strength: 256,
      randomBytes: (int size) {
        return Uint8List.fromList(shaValue.bytes);
      },
    );
  }
}
