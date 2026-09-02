import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as p;
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:photos/services/remote_assets_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late PathProviderPlatform previousPathProvider;

  setUp(() async {
    previousPathProvider = PathProviderPlatform.instance;
    tempDirectory = await Directory.systemTemp.createTemp(
      "remote_assets_service_test_",
    );
    PathProviderPlatform.instance = _FakePathProvider(tempDirectory.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPathProvider;
    await tempDirectory.delete(recursive: true);
  });

  test("deleteAsset removes every custom-named cache artifact", () async {
    const cacheFileName = "memory-music-track.mp3";
    const remotePath = "https://music.ente.com/track.mp3";
    final localPath = p.join(tempDirectory.path, "assets", cacheFileName);
    final artifacts = await _createAssetArtifacts(localPath);
    final unrelatedFile = File(
      p.join(tempDirectory.path, "assets", "unrelated.mp3"),
    );
    await unrelatedFile.writeAsString("unrelated");

    expect(
      await RemoteAssetsService.instance.hasAsset(
        remotePath,
        cacheFileName: cacheFileName,
      ),
      isTrue,
    );

    await RemoteAssetsService.instance.deleteAsset(
      remotePath,
      cacheFileName: cacheFileName,
    );

    for (final artifact in artifacts) {
      expect(await artifact.exists(), isFalse);
    }
    expect(await unrelatedFile.exists(), isTrue);

    await RemoteAssetsService.instance.deleteAsset(
      remotePath,
      cacheFileName: cacheFileName,
    );
  });

  test("deleteAsset retains the existing default cache-name mapping", () async {
    const remotePath = "https://models.ente.com/model.onnx";
    final localPath = p.join(
      tempDirectory.path,
      "assets",
      "models_ente_com_model_onnx",
    );
    final artifacts = await _createAssetArtifacts(localPath);

    await RemoteAssetsService.instance.deleteAsset(remotePath);

    for (final artifact in artifacts) {
      expect(await artifact.exists(), isFalse);
    }
  });
}

Future<List<File>> _createAssetArtifacts(String localPath) async {
  final artifacts = <File>[
    File(localPath),
    File("$localPath.temp"),
    File("$localPath.temp.resume.json"),
  ];
  for (final artifact in artifacts) {
    await artifact.create(recursive: true);
    await artifact.writeAsString("asset");
  }
  return artifacts;
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.applicationSupportPath);

  final String applicationSupportPath;

  @override
  Future<String?> getApplicationSupportPath() async => applicationSupportPath;
}
