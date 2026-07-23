import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:flutter/material.dart';

class ActionBarWidget extends StatefulWidget {
  final VoidCallback? onCancel;
  final Code code;

  const ActionBarWidget({
    required this.onCancel,
    required this.code,
    super.key,
  });

  @override
  State<ActionBarWidget> createState() => _ActionBarWidgetState();
}

class _ActionBarWidgetState extends State<ActionBarWidget> {
  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    return SizedBox(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          // left align the text
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.code.note.isNotEmpty)
              SelectableText(widget.code.note, style: textTheme.miniMuted),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  flex: 1,
                  child: Column(
                    children: [
                      SelectableText(
                        widget.code.issuerAccount,
                        style: textTheme.miniMuted,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        widget.onCancel?.call();
                      },
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(context.l10n.cancel, style: textTheme.mini),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
