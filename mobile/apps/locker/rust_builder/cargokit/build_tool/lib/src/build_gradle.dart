/// This is copied from Cargokit (which is the official way to use it currently)
/// Details: https://fzyzcjy.github.io/flutter_rust_bridge/manual/integrate/builtin

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'artifacts_provider.dart';
import 'builder.dart';
import 'environment.dart';
import 'options.dart';
import 'target.dart';

final log = Logger('build_gradle');

class BuildGradle {
  BuildGradle({required this.userOptions});

  final CargokitUserOptions userOptions;

  Future<void> build() async {
    final targets = Environment.targetPlatforms.map((arch) {
      final target = Target.forFlutterName(arch);
      if (target == null) {
        throw Exception(
          "Unknown darwin target or platform: $arch, ${Environment.darwinPlatformName}",
        );
      }
      return target;
    }).toList();

    final environment = BuildEnvironment.fromEnvironment(isAndroid: true);
    final provider = ArtifactProvider(
      environment: environment,
      userOptions: userOptions,
    );
    final artifacts = await provider.getArtifacts(targets);

    for (final target in targets) {
      final libs = artifacts[target]!;
      final outputDir = path.join(Environment.outputDir, target.android!);
      Directory(outputDir).createSync(recursive: true);

      for (final lib in libs) {
        if (lib.type == AritifactType.dylib) {
          File(lib.path).copySync(path.join(outputDir, lib.finalFileName));
        }
      }

      _copyAndroidCppRuntime(
        environment: environment,
        target: target,
        outputDir: outputDir,
      );
    }
  }

  void _copyAndroidCppRuntime({
    required BuildEnvironment environment,
    required Target target,
    required String outputDir,
  }) {
    final libDirName = _ndkLibDirName(target);
    if (libDirName == null) {
      return;
    }

    final sysrootLibDir = _findNdkSysrootLibDir(environment);
    if (sysrootLibDir == null) {
      return;
    }

    final source = File(
      path.join(sysrootLibDir.path, libDirName, 'libc++_shared.so'),
    );
    if (!source.existsSync()) {
      log.warning(
        'Could not find libc++_shared.so for ${target.android} at ${source.path}',
      );
      return;
    }

    final destination = File(path.join(outputDir, 'libc++_shared.so'));
    if (destination.existsSync()) {
      destination.deleteSync();
    }
    source.copySync(destination.path);
  }

  String? _ndkLibDirName(Target target) {
    return switch (target.android) {
      'armeabi-v7a' => 'arm-linux-androideabi',
      'arm64-v8a' => 'aarch64-linux-android',
      'x86' => 'i686-linux-android',
      'x86_64' => 'x86_64-linux-android',
      _ => null,
    };
  }

  Directory? _findNdkSysrootLibDir(BuildEnvironment environment) {
    final sdkPath = environment.androidSdkPath;
    final ndkVersion = environment.androidNdkVersion;
    if (sdkPath == null || ndkVersion == null) {
      log.warning('Android SDK path or NDK version is not set.');
      return null;
    }

    final prebuiltRoot = Directory(
      path.join(sdkPath, 'ndk', ndkVersion, 'toolchains', 'llvm', 'prebuilt'),
    );
    if (!prebuiltRoot.existsSync()) {
      log.warning(
        'NDK prebuilt directory does not exist: ${prebuiltRoot.path}',
      );
      return null;
    }

    for (final entry in prebuiltRoot.listSync()) {
      if (entry is! Directory) {
        continue;
      }
      final sysrootLibDir = Directory(
        path.join(entry.path, 'sysroot', 'usr', 'lib'),
      );
      if (sysrootLibDir.existsSync()) {
        return sysrootLibDir;
      }
    }

    log.warning('Could not locate NDK sysroot library directory.');
    return null;
  }
}
