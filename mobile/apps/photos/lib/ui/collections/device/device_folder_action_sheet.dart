import 'dart:math';

import 'package:collection/collection.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/models/device_collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/collections/device/device_folder_list_item.dart';
import 'package:photos/ui/viewer/file/thumbnail_widget.dart';

class LinkedDeviceMoveChoice {
  const LinkedDeviceMoveChoice({
    required this.includeLinkedSide,
    required this.remember,
  });

  final bool includeLinkedSide;
  final bool remember;
}

Future<LinkedDeviceMoveChoice?> showLinkedDeviceMoveSheet(
  BuildContext context, {
  required List<EnteFile> previews,
  required Set<String> linkedLocalIDs,
  required int selectedCount,
  required int eligibleCount,
  required bool deviceInitiated,
}) {
  return showBottomSheetComponent<LinkedDeviceMoveChoice>(
    context: context,
    builder: (_) => _LinkedDeviceMoveSheet(
      previews: previews,
      linkedLocalIDs: linkedLocalIDs,
      selectedCount: selectedCount,
      eligibleCount: eligibleCount,
      deviceInitiated: deviceInitiated,
    ),
  );
}

class _LinkedDeviceMoveSheet extends StatefulWidget {
  const _LinkedDeviceMoveSheet({
    required this.previews,
    required this.linkedLocalIDs,
    required this.selectedCount,
    required this.eligibleCount,
    required this.deviceInitiated,
  });

  final List<EnteFile> previews;
  final Set<String> linkedLocalIDs;
  final int selectedCount;
  final int eligibleCount;
  final bool deviceInitiated;

  @override
  State<_LinkedDeviceMoveSheet> createState() => _LinkedDeviceMoveSheetState();
}

class _LinkedDeviceMoveSheetState extends State<_LinkedDeviceMoveSheet> {
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final remaining = widget.selectedCount - widget.eligibleCount;
    final strings = context.strings;
    final title = widget.deviceInitiated
        ? strings.linkedDeviceMoveQuestion
        : strings.linkedDeviceMoveOnDeviceQuestion;
    return BottomSheetComponent(
      title: title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _PreviewRow(
            files: widget.previews,
            linkedLocalIDs: widget.linkedLocalIDs,
            totalCount: widget.selectedCount,
            deviceInitiated: widget.deviceInitiated,
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            remaining == 0
                ? strings.linkedDeviceMoveAllBackedUp(
                    count: widget.selectedCount,
                  )
                : widget.deviceInitiated
                ? strings.linkedDeviceMoveRemainingDeviceOnly(
                    eligibleCount: widget.eligibleCount,
                    selectedCount: widget.selectedCount,
                    count: remaining,
                  )
                : strings.linkedDeviceMoveRemainingEnteOnly(
                    eligibleCount: widget.eligibleCount,
                    selectedCount: widget.selectedCount,
                    count: remaining,
                  ),
            style: TextStyles.body.copyWith(
              color: context.componentColors.textLight,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          LabeledControlComponent(
            control: CheckboxComponent(
              selected: _remember,
              onChanged: (value) => setState(() => _remember = value),
            ),
            label: strings.setAsMyDefaultChoice,
            foreground: context.componentColors.textLight,
            onTap: () => setState(() => _remember = !_remember),
          ),
        ],
      ),
      actions: [
        ButtonComponent(
          label: widget.deviceInitiated
              ? strings.moveOnDeviceOnly
              : strings.moveInEnteOnly,
          variant: ButtonComponentVariant.neutral,
          shouldSurfaceExecutionStates: false,
          onTap: () => Navigator.of(context).pop(
            LinkedDeviceMoveChoice(
              includeLinkedSide: false,
              remember: _remember,
            ),
          ),
        ),
        ButtonComponent(
          label: strings.moveOnDeviceAndEnte,
          shouldSurfaceExecutionStates: false,
          onTap: () => Navigator.of(context).pop(
            LinkedDeviceMoveChoice(
              includeLinkedSide: true,
              remember: _remember,
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  static const _previewSize = 56.0;

  const _PreviewRow({
    required this.files,
    required this.linkedLocalIDs,
    required this.totalCount,
    required this.deviceInitiated,
  });

  final List<EnteFile> files;
  final Set<String> linkedLocalIDs;
  final int totalCount;
  final bool deviceInitiated;

  @override
  Widget build(BuildContext context) {
    final shown = files.take(4).toList(growable: false);
    return SizedBox(
      height: _previewSize,
      child: Row(
        children: [
          ...shown.map(
            (file) => Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    child: SizedBox(
                      width: _previewSize,
                      height: _previewSize,
                      child: ThumbnailWidget(file, rawThumbnail: true),
                    ),
                  ),
                  if (linkedLocalIDs.contains(file.localID))
                    Positioned(
                      left: Spacing.xs,
                      bottom: Spacing.xs,
                      child: Semantics(
                        label: deviceInitiated
                            ? context.strings.ente
                            : context.strings.onDevice,
                        child: HugeIcon(
                          icon: deviceInitiated
                              ? HugeIcons.strokeRoundedCloudSavingDone01
                              : HugeIcons.strokeRoundedSmartPhone01,
                          size: IconSizes.small,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (totalCount > shown.length)
            Container(
              width: _previewSize,
              height: _previewSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.sm),
                color: getEnteColorScheme(context).fillFaint,
              ),
              child: Text(
                '+${totalCount - shown.length}',
                style: TextStyles.bodyBold,
              ),
            ),
        ],
      ),
    );
  }
}

Future<DeviceCollection?> showDeviceFolderActionSheet(
  BuildContext context, {
  required Future<List<DeviceCollection>> destinations,
  required String title,
}) {
  final topPadding = MediaQuery.paddingOf(context).top;
  final bottomPadding = MediaQuery.paddingOf(context).bottom;
  final screenHeight = MediaQuery.sizeOf(context).height;
  const sheetHeaderHeight = 76.0;
  final sheetTopGap = screenHeight * 0.20;
  final height = max(
    0.0,
    screenHeight - topPadding - bottomPadding - sheetTopGap - sheetHeaderHeight,
  );

  return showBottomSheetComponent<DeviceCollection>(
    context: context,
    builder: (_) => BottomSheetComponent(
      title: title,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      content: SizedBox(
        height: height,
        child: DeviceFolderActionSheet(destinations: destinations),
      ),
    ),
  );
}

Future<bool> showBackedUpDeviceFolderCopyWarningSheet(
  BuildContext context, {
  required int backedUpFileCount,
}) async {
  final confirmed = await showBottomSheetComponent<bool>(
    context: context,
    builder: (sheetContext) => BottomSheetComponent(
      title: sheetContext.strings.createDuplicateBackupsQuestion,
      message: sheetContext.strings.copyAlreadyBackedUpFilesWarning(
        count: backedUpFileCount,
      ),
      illustration: Image.asset("assets/warning-grey.png"),
      closeTooltip: sheetContext.strings.close,
      closeResult: false,
      actions: [
        ButtonComponent(
          label: sheetContext.strings.copyAnyway,
          shouldSurfaceExecutionStates: false,
          onTap: () => Navigator.of(sheetContext).pop(true),
        ),
      ],
    ),
  );

  return confirmed == true;
}

class DeviceFolderActionSheet extends StatefulWidget {
  const DeviceFolderActionSheet({required this.destinations, super.key});

  final Future<List<DeviceCollection>> destinations;

  @override
  State<DeviceFolderActionSheet> createState() =>
      _DeviceFolderActionSheetState();
}

class _DeviceFolderActionSheetState extends State<DeviceFolderActionSheet> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextInputComponent(
          hintText: context.strings.searchByAlbumNameHint,
          prefix: HugeIcon(
            icon: HugeIcons.strokeRoundedSearch01,
            size: 18,
            color: context.componentColors.textLight,
          ),
          onChanged: (value) => setState(() => _searchQuery = value.trim()),
          isClearable: true,
          shouldUnfocusOnClearOrSubmit: true,
        ),
        const SizedBox(height: 24),
        Expanded(
          child: FutureBuilder<List<DeviceCollection>>(
            future: widget.destinations,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    context.strings.somethingWentWrong,
                    style: TextStyles.body.copyWith(
                      color: context.componentColors.textLight,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: EnteLoadingWidget());
              }
              final folders = snapshot.data!
                  .where(
                    (folder) => folder.name.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ),
                  )
                  .sortedByCompare(
                    (folder) => folder.name,
                    compareAsciiLowerCaseNatural,
                  );
              if (folders.isEmpty) {
                return Center(
                  child: Text(
                    context.strings.noResultsFound,
                    style: TextStyles.body.copyWith(
                      color: context.componentColors.textLight,
                    ),
                  ),
                );
              }
              return ListView.separated(
                itemCount: folders.length,
                itemBuilder: (context, index) {
                  final folder = folders[index];
                  return DeviceFolderListItem(
                    folder,
                    onTap: () => Navigator.of(context).pop(folder),
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(height: 8),
              );
            },
          ),
        ),
      ],
    );
  }
}
