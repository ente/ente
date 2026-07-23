import "dart:io";

import "package:ente_components/ente_components.dart";
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/freeable_space_info.dart';
import 'package:photos/ui/common/gradient_button.dart';
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
      appBar: AppBar(
        elevation: 0,
        title: Text(AppLocalizations.of(context).freeUpSpace),
      ),
      body: _getBody(),
    );
  }

  Widget _getBody() {
    Logger("FreeSpacePage").info(
      "Number of uploaded files: " + widget.status.localIDs.length.toString(),
    );
    Logger(
      "FreeSpacePage",
    ).info("Space consumed: " + widget.status.size.toString());
    return SingleChildScrollView(child: _getWidget(widget.status));
  }

  Widget _getWidget(FreeableSpaceInfo status) {
    final count = status.localIDs.length;
    final formattedCount = NumberFormat().format(count);
    final String textMessage = widget.clearSpaceForFolder
        ? AppLocalizations.of(
            context,
          ).filesBackedUpInAlbum(count: count, formattedNumber: formattedCount)
        : AppLocalizations.of(context).filesBackedUpFromDevice(
            count: count,
            formattedNumber: formattedCount,
          );
    final informationTextStyle = TextStyle(
      fontSize: 14,
      height: 1.3,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
      fontWeight: FontWeight.w500,
    );
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        Stack(
          alignment: Alignment.center,
          children: [
            isLightMode
                ? Image.asset(
                    'assets/loading_photos_background.png',
                    color: Colors.white.withValues(alpha: 0.4),
                    colorBlendMode: BlendMode.modulate,
                  )
                : Image.asset(
                    'assets/loading_photos_background_dark.png',
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Image.asset("assets/gallery_locked.png", height: 160),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 36, right: 40),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_done_outlined,
                color: Color.fromRGBO(45, 194, 98, 1.0),
              ),
              const Padding(padding: EdgeInsets.all(10)),
              Expanded(child: Text(textMessage, style: informationTextStyle)),
            ],
          ),
        ),
        const Padding(padding: EdgeInsets.all(12)),
        Padding(
          padding: const EdgeInsets.only(left: 36, right: 40),
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline,
                color: Color.fromRGBO(45, 194, 98, 1.0),
              ),
              const Padding(padding: EdgeInsets.all(10)),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).freeUpSpaceSaving(
                    count: count,
                    formattedSize: formatBytes(status.size),
                  ),
                  style: informationTextStyle,
                ),
              ),
            ],
          ),
        ),
        const Padding(padding: EdgeInsets.all(12)),
        Padding(
          padding: const EdgeInsets.only(left: 36, right: 40),
          child: Row(
            children: [
              const Icon(
                Icons.devices,
                color: Color.fromRGBO(45, 194, 98, 1.0),
              ),
              const Padding(padding: EdgeInsets.all(10)),
              Expanded(
                child: Text(
                  AppLocalizations.of(
                    context,
                  ).freeUpAccessPostDelete(count: count),
                  style: informationTextStyle,
                ),
              ),
            ],
          ),
        ),
        const Padding(padding: EdgeInsets.all(24)),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(60, 0, 60, 0),
          child: GradientButton(
            onTap: () async {
              await _showConfirmFreeSpaceSheet(context, status);
            },
            text: AppLocalizations.of(
              context,
            ).freeUpAmount(sizeInMBorGB: formatBytes(status.size)),
          ),
        ),
        const Padding(padding: EdgeInsets.all(24)),
      ],
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
