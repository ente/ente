import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_photos_platform/ente_photos_platform.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:photos/models/device_collection.dart';
import 'package:photos/services/device_folder_transfer_service.dart';
import 'package:photos/ui/collections/device/device_folder_list_item.dart';

Future<DeviceCollection?> showDeviceFolderTransferSheet(
  BuildContext context, {
  required DeviceFolderTransferOperation operation,
  required String title,
  required String? sourceFolderID,
}) => showBottomSheetComponent<DeviceCollection>(
  context: context,
  builder: (context) => DeviceFolderTransferSheet(
    title: title,
    loadFolders: () => DeviceFolderTransferService.instance.destinations(
      operation: operation,
      sourceFolderID: sourceFolderID,
    ),
  ),
);

class DeviceFolderTransferSheet extends StatefulWidget {
  const DeviceFolderTransferSheet({
    required this.title,
    required this.loadFolders,
    super.key,
  });

  final String title;

  final Future<List<DeviceCollection>> Function() loadFolders;

  @override
  State<DeviceFolderTransferSheet> createState() =>
      _DeviceFolderTransferSheetState();
}

class _DeviceFolderTransferSheetState extends State<DeviceFolderTransferSheet> {
  late Future<List<DeviceCollection>> _folders;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _folders = widget.loadFolders();
  }

  @override
  Widget build(BuildContext context) => BottomSheetComponent(
    title: widget.title,
    closeTooltip: context.strings.close,
    isKeyboardAware: true,
    isScrollable: true,
    shrinkWrap: true,
    content: SizedBox(
      height: math.max(
        kMinInteractiveDimension * 2 + Spacing.lg,
        (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom) *
            0.5,
      ),
      child: _folderList(context),
    ),
  );

  Widget _folderList(BuildContext context) => Column(
    children: [
      TextInputComponent(
        hintText: context.strings.searchByAlbumNameHint,
        isClearable: true,
        onChanged: (value) =>
            setState(() => _query = value.trim().toLowerCase()),
      ),
      const SizedBox(height: Spacing.lg),
      Expanded(
        child: FutureBuilder<List<DeviceCollection>>(
          future: _folders,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.strings.couldNotLoadAlbums,
                        style: TextStyles.body.copyWith(
                          color: context.componentColors.textLight,
                        ),
                      ),
                      const SizedBox(height: Spacing.md),
                      ButtonComponent(
                        label: context.strings.retry,
                        onTap: () async {
                          setState(() {
                            _folders = widget.loadFolders();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snapshot.hasData) return const EnteLoadingWidget();
            final folders = snapshot.data!
                .where((folder) => folder.name.toLowerCase().contains(_query))
                .sorted((a, b) => compareAsciiLowerCaseNatural(a.name, b.name));
            if (folders.isEmpty) {
              return Center(
                child: Text(
                  _query.isEmpty
                      ? context.strings.noEligibleDeviceAlbums
                      : context.strings.noResultsFound,
                  textAlign: TextAlign.center,
                  style: TextStyles.body.copyWith(
                    color: context.componentColors.textLight,
                  ),
                ),
              );
            }
            return ListView.builder(
              itemCount: folders.length,
              itemBuilder: (context, index) => DeviceFolderListItem(
                folders[index],
                onTap: () => Navigator.of(context).pop(folders[index]),
              ),
            );
          },
        ),
      ),
    ],
  );
}
