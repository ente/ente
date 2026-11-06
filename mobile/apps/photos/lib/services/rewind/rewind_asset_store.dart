import "dart:io";
import "dart:isolate";

import "package:archive/archive_io.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:path/path.dart" as path;
import "package:path_provider/path_provider.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:synchronized/synchronized.dart";

class RewindAssetStore {
  static const lilitaOne = "Lilita One";
  static const nunito = "Nunito";
  static const bagelFatOne = "Bagel Fat One";
  static const courierPrime = "Courier Prime";

  static const _version = "rewind-2026-v1";
  static const _url = "https://rewind-assets.ente.com/$_version.zip";
  static const _sha256 =
      "8bb3f26b794e00c25564ff1cdcb060d438ef2ee2b1aa41d6d8b5b5dfda5e429b";
  static const _fonts = {
    lilitaOne: "fonts/LilitaOne-Regular.ttf",
    nunito: "fonts/Nunito-Black.ttf",
    bagelFatOne: "fonts/BagelFatOne-Regular.ttf",
    courierPrime: "fonts/CourierPrime-Regular.ttf",
  };

  final _logger = Logger("RewindAssetStore");
  final _lock = Lock();
  String? _directory;
  var _fontsLoaded = false;

  File file(String name) => File(path.join(_directory!, name));

  Future<bool> prepare() => _lock.synchronized(() async {
    try {
      final directory = await _unpacked();
      await _loadFonts(directory);
      _directory = directory;
      return true;
    } catch (e, s) {
      _logger.warning("Rewind assets are not available", e, s);
      return false;
    }
  });

  static Future<String> _unpacked() async {
    final root = path.join(
      (await getApplicationSupportDirectory()).path,
      "rewind-assets",
    );
    final target = Directory(path.join(root, _version));
    if (await target.exists()) return target.path;
    final zip = await RemoteAssetsService.instance.getAsset(
      _url,
      expectedSha256: _sha256,
    );
    final zipPath = zip.path;
    final stagingPath = "${target.path}.unpacking";
    final staging = Directory(stagingPath);
    if (await staging.exists()) await staging.delete(recursive: true);
    await Isolate.run(() => _unzip(zipPath, stagingPath));
    await staging.rename(target.path);
    await RemoteAssetsService.instance.deleteAsset(_url);
    for (final entry in await Directory(root).list().toList()) {
      if (path.basename(entry.path) != _version) {
        await entry.delete(recursive: true);
      }
    }
    return target.path;
  }

  Future<void> _loadFonts(String directory) async {
    if (_fontsLoaded) return;
    for (final MapEntry(key: family, value: name) in _fonts.entries) {
      final bytes = await File(path.join(directory, name)).readAsBytes();
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
    _fontsLoaded = true;
  }
}

void _unzip(String zipPath, String outputPath) {
  final input = InputFileStream(zipPath);
  try {
    for (final entry in ZipDecoder().decodeStream(input)) {
      if (!entry.isFile) continue;
      final target = path.join(outputPath, path.normalize(entry.name));
      if (!path.isWithin(outputPath, target)) {
        throw FormatException("Unexpected entry ${entry.name}");
      }
      File(target)
        ..createSync(recursive: true)
        ..writeAsBytesSync(entry.content);
    }
  } finally {
    input.closeSync();
  }
}
