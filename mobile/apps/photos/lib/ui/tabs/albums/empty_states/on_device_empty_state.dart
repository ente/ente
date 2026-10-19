import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/ui/common/backup_flow_helper.dart";
import "package:photos/ui/tabs/albums/empty_states/empty_state_layout.dart";

class OnDeviceEmptyState extends StatelessWidget {
  const OnDeviceEmptyState.permission({this.onFoldersSelected, super.key})
    : _mode = _OnDeviceEmptyStateMode.permission;

  const OnDeviceEmptyState.noFolders({super.key})
    : _mode = _OnDeviceEmptyStateMode.noFolders,
      onFoldersSelected = null;

  static const _permissionIllustrationHeight = 130.3;
  static const _noFoldersIllustrationHeight = 142.3;
  static const _noFoldersDescriptionWidth = 299.0;

  final _OnDeviceEmptyStateMode _mode;
  final VoidCallback? onFoldersSelected;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return switch (_mode) {
      _OnDeviceEmptyStateMode.permission => EmptyStateLayout(
        assetPath: "assets/on_device.png",
        assetHeight: _permissionIllustrationHeight,
        title: strings.allowAccessToYourPhotos,
        description: strings.albumsOnDevicePermissionDescription,
        action: ButtonComponent(
          label: strings.albumsOnDevicePermissionCta,
          shouldSurfaceExecutionStates: false,
          onTap: () => _selectFolders(context),
        ),
      ),
      _OnDeviceEmptyStateMode.noFolders => EmptyStateLayout(
        assetPath: "assets/on_device_empty.png",
        assetHeight: _noFoldersIllustrationHeight,
        title: strings.noAlbumsOnThisDevice,
        description: strings.startSnappingYourPhotosWillShowUpHere,
        descriptionWidth: _noFoldersDescriptionWidth,
      ),
    };
  }

  Future<void> _selectFolders(BuildContext context) async {
    await handleFolderSelectionBackupFlow(context);
    onFoldersSelected?.call();
  }
}

enum _OnDeviceEmptyStateMode { permission, noFolders }
