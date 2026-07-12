import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/models/button_type.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/share_utils.dart';
import 'package:ente_auth/utils/totp_util.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class ShareCodeDialog extends StatefulWidget {
  final Code code;
  const ShareCodeDialog({super.key, required this.code});

  @override
  State<ShareCodeDialog> createState() => _ShareCodeDialogState();
}

class _ShareCodeDialogState extends State<ShareCodeDialog> {
  final Logger logger = Logger('_ShareCodeDialogState');
  final List<int> _durationInMins = [2, 5, 10];
  late int selectedValue;

  String getItemLabel(int min) {
    if (min == 60) return '1 hour';
    if (min > 60) {
      var hour = '${min ~/ 60}';
      if (min % 60 == 0) return '$hour hour';
      var minx = '${min % 60}';
      return '$hour hr $minx min';
    }
    return '$min min';
  }

  @override
  void initState() {
    super.initState();
    selectedValue = _durationInMins[1];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.shareCodes),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.shareCodesDuration),
          const SizedBox(height: 10),
          DropdownButtonHideUnderline(
            child: DropdownButton2(
              hint: Text(context.l10n.selectAnOption),
              items: _durationInMins
                  .map(
                    (item) => DropdownMenuItem<int>(
                      value: item,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(getItemLabel(item)),
                      ),
                    ),
                  )
                  .toList(),
              value: selectedValue,
              onChanged: (value) {
                setState(() {
                  selectedValue = value ?? 2;
                });
              },
            ),
          ),
        ],
      ),
      actions: [
        ButtonWidget(
          buttonType: ButtonType.primary,
          buttonSize: ButtonSize.large,
          labelText: context.l10n.share,
          onTap: () async {
            try {
              if (!context.mounted) return;
              await shareCode(selectedValue);
              if (!context.mounted) return;
              Navigator.of(context).pop();
            } catch (e, s) {
              logger.severe('Failed to generate shared codes', e, s);
              showGenericErrorDialog(context: context, error: e).ignore();
            }
          },
        ),
        const SizedBox(height: 8),
        ButtonWidget(
          buttonType: ButtonType.secondary,
          buttonSize: ButtonSize.large,
          labelText: context.l10n.cancel,
          onTap: () async {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Future<void> shareCode(int durationInMin) async {
    final int count = ((durationInMin * 60.0) / widget.code.period).ceil();
    final result = generateFutureTotpCodes(widget.code, count);
    Map<String, dynamic> data = {
      'startTime': result.$1,
      'step': widget.code.period,
      'codes': result.$2.join(","),
    };
    final Uint8List key = _generate256BitKey();
    Uint8List input = utf8.encode(jsonEncode(data));
    final encResult = await CryptoUtil.encryptData(input, key);
    String url =
        'https://auth.ente.com/share?data=${_uint8ListToUrlSafeBase64(encResult.encryptedData!)}&header=${_uint8ListToUrlSafeBase64(encResult.header!)}#${_uint8ListToUrlSafeBase64(key)}';
    try {
      if (!mounted) return;
      await shareText(url, context: context);
    } catch (e) {
      logger.warning('Failed to share code: ${e.toString()}');
    }
  }

  String _uint8ListToUrlSafeBase64(Uint8List data) {
    String base64Str = base64UrlEncode(data);
    return base64Str.replaceAll('=', '');
  }

  Uint8List _generate256BitKey() {
    final random = Random.secure();
    final bytes = Uint8List(32); // 32 bytes = 32 * 8 bits = 256 bits
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(
        256,
      ); // Generates a random number between 0 and 255 (1 byte)
    }
    return bytes;
  }
}

void showShareDialog(BuildContext context, Code code) {
  if (!code.type.canShareCodes) {
    return;
  }
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return ShareCodeDialog(code: code);
    },
  );
}
