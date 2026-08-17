// This is copied from Cargokit (which is the official way to use it currently)
// Details: https://fzyzcjy.github.io/flutter_rust_bridge/manual/integrate/builtin

import 'dart:io';

extension on String {
  String resolveSymlink() => File(this).resolveSymbolicLinksSync();
}

class Environment {
  static String get configuration =>
      _getEnv("CARGOKIT_CONFIGURATION").toLowerCase();

  static bool get isDebug => configuration == 'debug';
  static bool get isRelease => configuration == 'release';

  static String get targetTempDir => _getEnv("CARGOKIT_TARGET_TEMP_DIR");

  static String get outputDir => _getEnvPath('CARGOKIT_OUTPUT_DIR');

  static String get manifestDir => _getEnvPath('CARGOKIT_MANIFEST_DIR');

  // Symlinks are not resolved on purpose.
  static String get rootProjectDir => _getEnv('CARGOKIT_ROOT_PROJECT_DIR');

  static String get darwinPlatformName =>
      _getEnv("CARGOKIT_DARWIN_PLATFORM_NAME");

  static List<String> get darwinArchs =>
      _getEnv("CARGOKIT_DARWIN_ARCHS").split(' ');

  static String get minSdkVersion => _getEnv("CARGOKIT_MIN_SDK_VERSION");
  static String get ndkVersion => _getEnv("CARGOKIT_NDK_VERSION");
  static String get sdkPath => _getEnvPath("CARGOKIT_SDK_DIR");
  static String get javaHome => _getEnvPath("CARGOKIT_JAVA_HOME");
  static List<String> get targetPlatforms =>
      _getEnv("CARGOKIT_TARGET_PLATFORMS").split(',');

  static String get targetPlatform => _getEnv("CARGOKIT_TARGET_PLATFORM");

  static String _getEnv(String key) {
    final res = Platform.environment[key];
    if (res == null) {
      throw Exception("Missing environment variable $key");
    }
    return res;
  }

  static String _getEnvPath(String key) {
    final res = _getEnv(key);
    if (Directory(res).existsSync()) {
      return res.resolveSymlink();
    } else {
      return res;
    }
  }
}
