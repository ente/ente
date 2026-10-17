import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/service_locator.dart";
import "package:receive_sharing_intent/receive_sharing_intent.dart";

Future<bool> confirmSharedMediaBackup(
  BuildContext context,
  List<SharedMediaFile> files,
) async {
  final hasPhotos = files.any(
    (file) =>
        file.type == SharedMediaType.image ||
        (file.mimeType?.startsWith("image/") ?? false),
  );
  if (!hasPhotos || localSettings.isSharedPhotoLocationWarningDismissed) {
    return true;
  }

  var dontShowAgain = false;
  final confirmed = await showBottomSheetComponent<bool>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) {
        final l10n = context.strings;
        return SingleChildScrollView(
          child: BottomSheetComponent(
            title: l10n.sharedPhotoLocationWarningTitle,
            message: l10n.sharedPhotoLocationWarningMessage(
              addFromDevice: l10n.addFromDevice,
            ),
            illustration: Image.asset("assets/warning-grey.png"),
            closeTooltip: l10n.close,
            closeResult: false,
            actions: [
              ButtonComponent(
                label: l10n.addAnyway,
                shouldSurfaceExecutionStates: false,
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  child: MergeSemantics(
                    child: Semantics(
                      checked: dontShowAgain,
                      child: LabeledControlComponent(
                        control: CheckboxComponent(
                          selected: dontShowAgain,
                          onChanged: (value) =>
                              setState(() => dontShowAgain = value),
                        ),
                        label: l10n.dontShowAgain,
                        foreground: context.componentColors.textLight,
                        onTap: () =>
                            setState(() => dontShowAgain = !dontShowAgain),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  if (confirmed != true) return false;
  if (dontShowAgain) await localSettings.dismissSharedPhotoLocationWarning();
  return true;
}
