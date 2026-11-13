import "dart:convert";

import 'package:bip39/bip39.dart' as bip39;
import "package:crypto/crypto.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/services/account/user_service.dart";
import 'package:photos/ui/components/buttons/button_widget.dart';
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/utils/share_util.dart";

Future<void> showVerifyIdentitySheet(
  BuildContext context, {
  required bool self,
  String email = '',
  String? title,
}) {
  return showBottomSheetComponent<void>(
    context: context,
    builder: (sheetContext) => BottomSheetComponent(
      title: title ?? sheetContext.strings.verify,
      content: _VerifyIdentitySheetContent(self: self, email: email),
    ),
  );
}

class _VerifyIdentitySheetContent extends StatefulWidget {
  final String email;

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
        ? context.strings.thisIsYourVerificationId
        : context.strings.thisIsPersonVerificationId(email: widget.email);
    final String bottomText = widget.self
        ? context.strings.someoneSharingAlbumsWithYouShouldSeeTheSameId
        : context.strings.howToViewShareeVerificationID;

    final colors = context.componentColors;

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
                  context.strings.emailNoEnteAccountPhotos(email: widget.email),
                  style: TextStyles.body.copyWith(color: colors.textLight),
                ),
                const SizedBox(height: 20),
                ButtonWidget(
                  buttonType: ButtonType.neutral,
                  icon: Icons.adaptive.share,
                  labelText: context.strings.sendInvite,
                  onTap: () async {
                    await shareText(
                      context.strings.shareTextRecommendUsingEnteForPhotos,
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
                style: TextStyles.body.copyWith(color: colors.textLight),
              ),
              const SizedBox(height: 20),
              _verificationIDSheetWidget(context, publicKey),
              const SizedBox(height: 20),
              Text(
                bottomText,
                style: TextStyles.body.copyWith(color: colors.textLight),
              ),
            ],
          );
        } else if (snapshot.hasError) {
          Logger(
            "VerificationID",
          ).severe("failed to end userID", snapshot.error);
          return Text(
            context.strings.somethingWentWrong,
            style: TextStyles.large.copyWith(color: colors.textLight),
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
      return "";
    }
    return userPublicKey;
  }

  Widget _verificationIDSheetWidget(BuildContext context, String publicKey) {
    final colors = context.componentColors;
    final String verificationID = _generateVerificationID(publicKey);

    return GestureDetector(
      onTap: () => _shareVerificationID(context, verificationID),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: colors.primary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        width: double.infinity,
        child: Text(
          verificationID,
          style: TextStyles.large.copyWith(
            color: colors.textReverse,
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
          ? context.strings.shareMyVerificationID(
              verificationID: verificationID,
            )
          : context.strings.shareTextConfirmOthersVerificationID(
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
