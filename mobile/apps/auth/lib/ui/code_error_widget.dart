import 'package:ente_auth/ente_theme_data.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/common/gradient_button.dart';
import 'package:ente_auth/ui/linear_progress_widget.dart';
import 'package:ente_auth/ui/tools/debug/raw_codes_viewer.dart';
import 'package:ente_auth/utils/email_util.dart';
import 'package:flutter/material.dart';

class CodeErrorWidget extends StatelessWidget {
  const CodeErrorWidget({super.key, required this.errors});

  final List<Code> errors;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return Container(
      height: 132,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.codeCardBackgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 3,
              child: LinearProgressWidget(
                color: colorScheme.errorCodeProgressColor,
                fractionOfStorage: 1,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(width: 8),
                Align(
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.info,
                    size: 18,
                    color: colorScheme.infoIconColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.error,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.errorCardTextColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                context.l10n.somethingWentWrongParsingCode(errors.length),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Spacer(),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                children: [
                  SizedBox(
                    width: 102,
                    height: 28,
                    child: GradientButton(
                      text: context.l10n.viewRawCodes,
                      fontSize: 10,
                      onTap: () async {
                        await showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return RawCodesViewer(errors);
                          },
                          barrierColor: Colors.black87,
                          barrierDismissible: false,
                        );
                      },
                      borderWidth: 0.6,
                      borderRadius: 6,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 102,
                    height: 28,
                    child: GradientButton(
                      text: context.l10n.contactSupport,
                      fontSize: 10,
                      onTap: () async {
                        await sendEmail(context, to: "support@ente.com");
                      },
                      borderWidth: 0.6,
                      borderRadius: 6,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
