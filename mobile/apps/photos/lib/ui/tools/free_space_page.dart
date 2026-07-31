import "dart:io";

import "package:ente_components/ente_components.dart";
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/freeable_space_info.dart';
import "package:photos/ui/notification/toast.dart";
import 'package:photos/utils/delete_file_util.dart';

class FreeSpacePage extends StatefulWidget {
  final FreeableSpaceInfo status;
  final bool clearSpaceForFolder;

  const FreeSpacePage(
    this.status, {
    super.key,
    this.clearSpaceForFolder = false,
  });

  @override
  State<FreeSpacePage> createState() => _FreeSpacePageState();
}

class _FreeSpacePageState extends State<FreeSpacePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.componentColors.backgroundBase,
      body: AppBarComponent(
        title: AppLocalizations.of(context).freeUpDeviceSpace,
        backgroundColor: context.componentColors.backgroundBase,
        slivers: [
          SliverSafeArea(
            top: false,
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: _getBody(widget.status),
            ),
          ),
        ],
      ),
    );
  }

  Widget _getBody(FreeableSpaceInfo status) {
    Logger(
      "FreeSpacePage",
    ).info("Number of uploaded files: " + status.localIDs.length.toString());
    Logger("FreeSpacePage").info("Space consumed: " + status.size.toString());
    final count = status.localIDs.length;
    final formattedCount = NumberFormat().format(count);
    final formattedSize = formatBytes(status.size);
    final l10n = AppLocalizations.of(context);
    final colors = context.componentColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Align(
        alignment: const Alignment(0, -0.2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset("assets/on_ente.png", width: 260, fit: BoxFit.contain),
            const SizedBox(height: 42),
            Text(
              l10n.reclaimSpace(sizeInMBorGB: formattedSize),
              textAlign: TextAlign.center,
              style: TextStyles.display2.copyWith(color: colors.textBase),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 300,
              child: Text(
                widget.clearSpaceForFolder
                    ? l10n.filesInAlbumSafelyOnEnte(
                        count: count,
                        formattedNumber: formattedCount,
                      )
                    : l10n.filesSafelyOnEnte(
                        count: count,
                        formattedNumber: formattedCount,
                      ),
                textAlign: TextAlign.center,
                style: TextStyles.mini.copyWith(color: colors.textLight),
              ),
            ),
            const SizedBox(height: 32),
            ButtonComponent(
              shouldSurfaceExecutionStates: false,
              onTap: () async {
                await _showConfirmFreeSpaceSheet(context, status);
              },
              label: l10n.freeUpAmount(sizeInMBorGB: formattedSize),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _freeStorage(FreeableSpaceInfo status) async {
    bool isSuccess = await deleteLocalFiles(context, status.localIDs);

    if (isSuccess == false) {
      if (!mounted) return;
      isSuccess = await deleteLocalFilesAfterRemovingAlreadyDeletedIDs(
        context,
        status.localIDs,
      );
    }

    if (isSuccess == false && Platform.isAndroid) {
      if (!mounted) return;
      isSuccess = await retryFreeUpSpaceAfterRemovingAssetsNonExistingInDisk(
        context,
      );
    }

    if (isSuccess) {
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      if (!mounted) return;
      showToast(context, AppLocalizations.of(context).couldNotFreeUpSpace);
    }
  }

  Future<void> _showConfirmFreeSpaceSheet(
    BuildContext context,
    FreeableSpaceInfo status,
  ) async {
    final l10n = AppLocalizations.of(context);
    await showBottomSheetComponent(
      context: context,
      builder: (_) => BottomSheetComponent(
        title: l10n.areYouSure,
        message: l10n.freeUpDeviceSpaceConfirmDesc(
          count: status.localIDs.length,
        ),
        illustration: Image.asset("assets/warning-red.png"),
        actions: [
          ButtonComponent(
            label: l10n.yesDelete,
            variant: .critical,
            onTap: () async {
              Navigator.of(context).pop();
              await _freeStorage(status);
            },
          ),
        ],
      ),
    );
  }
}
