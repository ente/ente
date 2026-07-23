import 'dart:io';

import 'package:ente_strings/extensions.dart';
import "package:ente_ui/components/base_bottom_sheet.dart";
import 'package:ente_ui/components/buttons/button_widget.dart';
import "package:ente_ui/components/buttons/gradient_button.dart";
import 'package:ente_ui/components/buttons/models/button_type.dart';
import 'package:ente_ui/components/dialog_widget.dart';
import "package:ente_ui/theme/ente_theme.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareDialog(
  BuildContext context,
  String title, {
  required Function saveAction,
  required Function sendAction,
}) async {
  final l10n = context.strings;
  await showDialogWidget(
    context: context,
    title: title,
    body: Platform.isLinux || Platform.isWindows
        ? l10n.saveOnlyDescription
        : l10n.saveOrSendDescription,
    buttons: [
      ButtonWidget(
        isInAlert: true,
        buttonType: ButtonType.neutral,
        labelText: l10n.save,
        buttonAction: ButtonAction.first,
        shouldSurfaceExecutionStates: false,
        onTap: () async {
          await saveAction();
        },
      ),
      if (!Platform.isWindows && !Platform.isLinux)
        ButtonWidget(
          isInAlert: true,
          buttonType: ButtonType.secondary,
          labelText: l10n.send,
          buttonAction: ButtonAction.second,
          onTap: () async {
            await sendAction();
          },
        ),
      ButtonWidget(
        isInAlert: true,
        buttonType: ButtonType.secondary,
        labelText: l10n.cancel,
        buttonAction: ButtonAction.cancel,
      ),
    ],
  );
}

Future<void> showShareSheet(
  BuildContext context,
  String title, {
  required Function saveAction,
  required Function sendAction,
}) async {
  return showBaseBottomSheet(
    context,
    headerSpacing: 20,
    title: title,
    child: Builder(
      builder: (context) {
        final textTheme = getEnteTextTheme(context);
        final colorScheme = getEnteColorScheme(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Platform.isLinux || Platform.isWindows
                  ? context.strings.saveOnlyDescription
                  : context.strings.saveOrSendDescription,
              style: textTheme.body.copyWith(color: colorScheme.textMuted),
            ),
            const SizedBox(height: 20),
            GradientButton(
              onTap: () async {
                await saveAction();
              },
              text: context.strings.save,
            ),
            if (!Platform.isWindows && !Platform.isLinux)
              const SizedBox(height: 20),
            if (!Platform.isWindows && !Platform.isLinux)
              GestureDetector(
                onTap: () async {
                  await sendAction();
                },
                child: Text(
                  context.strings.send,
                  style: textTheme.bodyBold.copyWith(
                    color: colorScheme.primary700,
                    decorationColor: colorScheme.primary700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

Rect _sharePosOrigin(BuildContext? context, GlobalKey? key) {
  late final Rect rect;
  if (context != null) {
    rect = shareButtonRect(context, key);
  } else {
    rect = const Offset(20.0, 20.0) & const Size(10, 10);
  }
  return rect;
}

/// Returns the rect of button if context and key are not null
/// If key is null, returned rect will be at the center of the screen
Rect shareButtonRect(BuildContext context, GlobalKey? shareButtonKey) {
  Size size = MediaQuery.sizeOf(context);
  final RenderObject? renderObject = shareButtonKey?.currentContext
      ?.findRenderObject();
  RenderBox? renderBox;
  if (renderObject != null && renderObject is RenderBox) {
    renderBox = renderObject;
  }
  if (renderBox == null) {
    return Rect.fromLTWH(0, 0, size.width, size.height / 2);
  }
  size = renderBox.size;
  final Offset position = renderBox.localToGlobal(Offset.zero);
  return Rect.fromCenter(
    center: position + Offset(size.width / 2, size.height / 2),
    width: size.width,
    height: size.height,
  );
}

Future<ShareResult> shareText(
  String text, {
  BuildContext? context,
  GlobalKey? key,
}) async {
  try {
    final sharePosOrigin = _sharePosOrigin(context, key);
    return SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: sharePosOrigin),
    );
  } catch (e, s) {
    Logger("ShareUtil").severe("failed to share text", e, s);
    return ShareResult.unavailable;
  }
}

Future<ShareResult> shareFiles(
  List<XFile> files, {
  BuildContext? context,
  GlobalKey? key,
  String? text,
}) async {
  try {
    final sharePosOrigin = _sharePosOrigin(context, key);
    return SharePlus.instance.share(
      ShareParams(
        files: files,
        text: text,
        sharePositionOrigin: sharePosOrigin,
      ),
    );
  } catch (e, s) {
    Logger("ShareUtil").severe("failed to share files", e, s);
    return ShareResult.unavailable;
  }
}
