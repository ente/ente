import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/common/backup_flow_helper.dart";
import "package:photos/ui/tabs/albums/empty_states/empty_state_feature_row.dart";

class OnDeviceEmptyState extends StatelessWidget {
  const OnDeviceEmptyState.permission({this.onFoldersSelected, super.key})
    : _mode = _OnDeviceEmptyStateMode.permission;

  const OnDeviceEmptyState.noFolders({this.onFoldersSelected, super.key})
    : _mode = _OnDeviceEmptyStateMode.noFolders;

  static const _permissionTopPadding = 12.0;
  static const _permissionSectionSpacing = 48.0;

  static const _contentWidth = 343.0;
  static const _featureWidth = 300.0;

  final _OnDeviceEmptyStateMode _mode;
  final VoidCallback? onFoldersSelected;

  @override
  Widget build(BuildContext context) {
    if (_mode == _OnDeviceEmptyStateMode.permission) {
      return _buildPermissionState(context);
    }
    return _buildNoFoldersState(context);
  }

  Widget _buildPermissionState(BuildContext context) {
    final colors = context.componentColors;
    final strings = AppLocalizations.of(context);
    final bottomPadding = 64 + MediaQuery.paddingOf(context).bottom + 32;
    final features = [
      strings.albumsOnDevicePermissionFeatureAllowAccessFaceRecognition,
      strings.albumsOnDevicePermissionFeatureLocalProcessing,
      strings.albumsOnDevicePermissionFeatureControlUploads,
    ];

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          _permissionTopPadding,
          16,
          bottomPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset("assets/on_device.png"),
                  const SizedBox(height: _permissionSectionSpacing),
                  Text(
                    strings.allowAccessToYourPhotos,
                    textAlign: TextAlign.center,
                    style: TextStyles.display2.copyWith(color: colors.textBase),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: _featureWidth,
                    child: Column(
                      children: [
                        EmptyStateBulletFeatureRow(label: features[0]),
                        const SizedBox(height: 12),
                        EmptyStateBulletFeatureRow(label: features[1]),
                        const SizedBox(height: 12),
                        EmptyStateBulletFeatureRow(label: features[2]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: _permissionSectionSpacing),
            ButtonComponent(
              label: strings.albumsOnDevicePermissionCta,
              shouldSurfaceExecutionStates: false,
              onTap: () => _selectFolders(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoFoldersState(BuildContext context) {
    final colors = context.componentColors;
    final strings = AppLocalizations.of(context);
    final bottomPadding = 64 + MediaQuery.paddingOf(context).bottom + 32;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
      child: Center(
        child: SizedBox(
          width: _contentWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset("assets/on_device_empty.png", fit: BoxFit.contain),
              const SizedBox(height: _permissionSectionSpacing),
              SizedBox(
                width: _contentWidth,
                child: Text(
                  strings.noAlbumsOnThisDevice,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: "Nunito",
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    height: 28 / 24,
                    letterSpacing: 0,
                    color: colors.textBase,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.startSnappingYourPhotosWillShowUpHere,
                textAlign: TextAlign.center,
                style: TextStyles.mini.copyWith(color: colors.textLight),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectFolders(BuildContext context) async {
    await handleFolderSelectionBackupFlow(context);
    onFoldersSelected?.call();
  }
}

enum _OnDeviceEmptyStateMode { permission, noFolders }
