import "package:photo_manager/photo_manager.dart";
import "package:shared_preferences/shared_preferences.dart";

class PermissionService {
  static const kHasGrantedPermissionsKey = "has_granted_permissions";
  static const kPermissionStateKey = "permission_state";
  static const _photoLibraryAddRequestOption = PermissionRequestOption(
    iosAccessLevel: IosAccessLevel.addOnly,
  );
  final SharedPreferences _prefs;
  PermissionService(this._prefs);

  Future<PermissionState> requestPhotoMangerPermissions() {
    return PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: true,
        ),
      ),
    );
  }

  Future<PermissionState> requestPhotoLibraryAddPermission() async {
    final state = await PhotoManager.getPermissionState(
      requestOption: _photoLibraryAddRequestOption,
    );
    return state == PermissionState.notDetermined
        ? PhotoManager.requestPermissionExtend(
            requestOption: _photoLibraryAddRequestOption,
          )
        : state;
  }

  bool hasGrantedPermissions() {
    return _prefs.getBool(kHasGrantedPermissionsKey) ?? false;
  }

  bool hasGrantedLimitedPermissions() {
    return _prefs.getString(kPermissionStateKey) ==
        PermissionState.limited.toString();
  }

  bool hasGrantedFullPermission() {
    return (_prefs.getString(kPermissionStateKey) ?? '') ==
        PermissionState.authorized.toString();
  }

  Future<void> onUpdatePermission(PermissionState state) async {
    await _prefs.setBool(kHasGrantedPermissionsKey, true);
    await _prefs.setString(kPermissionStateKey, state.toString());
  }

  Future<PermissionState> getPermissionState() {
    return PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: true,
        ),
      ),
    );
  }
}
