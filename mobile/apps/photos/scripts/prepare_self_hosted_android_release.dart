import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;
import "package:photos/core/network/endpoint_policy.dart";

const preparationToolName = "ente-self-hosted-android-release-preparer";
const preparationToolVersion = "1.0.0";
const releaseManifestSchemaVersion = 1;

const expectedPackageName = "me.vanton.ente.photos.selfhosted";
const expectedSigningCertificateSha256 =
    "9f0a5f39668e7098d097745931bcb8fc392d50da877cf349a2b20e2db1a4ce69";
const expectedMinSdk = 26;
const expectedTargetSdk = 36;
const expectedCompileSdk = 36;
const expectedAbis = <String>{"arm64-v8a", "armeabi-v7a"};

const _usage = """
Prepare and audit a signed configurable Ente Photos Android release.

Usage:
  ./scripts/prepare_self_hosted_android_release.sh \\
    --output-dir /absolute/path/outside/the/repository

Required environment:
  ENTE_SELF_HOSTED_ENDPOINT   Canonicalizable HTTPS Museum origin.
  ANDROID_HOME                Android SDK containing aapt2 and apksigner.

The existing build wrapper also honors FLUTTER_BIN and DART_BIN. Release
signing continues to use ignored android/key.properties or SIGNING_* variables.
""";

Future<void> main(List<String> arguments) async {
  try {
    final options = PreparationOptions.parse(
      arguments,
      environment: Platform.environment,
    );
    if (options.showHelp) {
      stdout.write(_usage);
      return;
    }

    final result = await prepareSelfHostedAndroidRelease(options);
    stdout.writeln();
    stdout.writeln("Prepared audited Android release:");
    stdout.writeln("  APK: ${result.apkPath}");
    stdout.writeln("  Manifest: ${result.manifestPath}");
    stdout.writeln("  SHA-256: ${result.sha256}");
    stdout.writeln("  Source: ${result.sourceCommitUrl}");
  } on ReleasePreparationException catch (error) {
    stderr.writeln("Release preparation failed: ${error.message}");
    exitCode = error.exitCode;
  } on Object catch (error) {
    stderr.writeln("Release preparation failed unexpectedly: $error");
    exitCode = 70;
  }
}

class PreparationOptions {
  PreparationOptions({
    required this.outputDirectory,
    required this.endpoint,
    required this.environment,
    this.showHelp = false,
  });

  factory PreparationOptions.parse(
    List<String> arguments, {
    required Map<String, String> environment,
  }) {
    if (arguments.length == 1 &&
        (arguments.single == "--help" || arguments.single == "-h")) {
      return PreparationOptions(
        outputDirectory: "",
        endpoint: "",
        environment: environment,
        showHelp: true,
      );
    }

    String? outputDirectory;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == "--output-dir") {
        if (index + 1 >= arguments.length) {
          throw const ReleasePreparationException(
            "--output-dir requires a value.",
            exitCode: 64,
          );
        }
        outputDirectory = arguments[++index];
      } else if (argument.startsWith("--output-dir=")) {
        outputDirectory = argument.substring("--output-dir=".length);
      } else {
        throw ReleasePreparationException(
          "Unknown argument '$argument'.\n\n$_usage",
          exitCode: 64,
        );
      }
    }

    outputDirectory ??= environment["ENTE_ANDROID_RELEASE_OUTPUT_DIR"];
    if (outputDirectory == null || outputDirectory.trim().isEmpty) {
      throw const ReleasePreparationException(
        "Provide --output-dir or ENTE_ANDROID_RELEASE_OUTPUT_DIR.",
        exitCode: 64,
      );
    }
    if (!p.isAbsolute(outputDirectory)) {
      throw const ReleasePreparationException(
        "The release output directory must be an absolute path.",
        exitCode: 64,
      );
    }

    final endpoint = environment["ENTE_SELF_HOSTED_ENDPOINT"];
    if (endpoint == null || endpoint.trim().isEmpty) {
      throw const ReleasePreparationException(
        "ENTE_SELF_HOSTED_ENDPOINT is required.",
        exitCode: 64,
      );
    }

    return PreparationOptions(
      outputDirectory: p.normalize(outputDirectory),
      endpoint: endpoint,
      environment: environment,
    );
  }

  final String outputDirectory;
  final String endpoint;
  final Map<String, String> environment;
  final bool showHelp;
}

class ReleasePreparationResult {
  const ReleasePreparationResult({
    required this.apkPath,
    required this.manifestPath,
    required this.sha256,
    required this.sourceCommitUrl,
  });

  final String apkPath;
  final String manifestPath;
  final String sha256;
  final String sourceCommitUrl;
}

class ReleasePreparationException implements Exception {
  const ReleasePreparationException(this.message, {this.exitCode = 66});

  final String message;
  final int exitCode;

  @override
  String toString() => message;
}

class ReleaseVersion {
  const ReleaseVersion(this.name, this.code);

  final String name;
  final int code;
}

class AndroidReleaseAudit {
  const AndroidReleaseAudit({
    required this.packageName,
    required this.version,
    required this.minSdk,
    required this.targetSdk,
    required this.compileSdk,
    required this.abis,
    required this.debuggable,
    required this.signingCertificateSha256,
    required this.signatureSchemes,
    required this.sha256,
    required this.sizeBytes,
  });

  final String packageName;
  final ReleaseVersion version;
  final int minSdk;
  final int targetSdk;
  final int compileSdk;
  final Set<String> abis;
  final bool debuggable;
  final String signingCertificateSha256;
  final Map<String, bool> signatureSchemes;
  final String sha256;
  final int sizeBytes;
}

class AaptBadging {
  const AaptBadging({
    required this.packageName,
    required this.version,
    required this.minSdk,
    required this.targetSdk,
    required this.compileSdk,
    required this.abis,
  });

  final String packageName;
  final ReleaseVersion version;
  final int minSdk;
  final int targetSdk;
  final int compileSdk;
  final Set<String> abis;
}

class ApkSignerAudit {
  const ApkSignerAudit({
    required this.certificateSha256,
    required this.signerCount,
    required this.signatureSchemes,
  });

  final String certificateSha256;
  final int signerCount;
  final Map<String, bool> signatureSchemes;
}

Future<ReleasePreparationResult> prepareSelfHostedAndroidRelease(
  PreparationOptions options,
) async {
  final scriptPath = p.normalize(Platform.script.toFilePath());
  final appDirectory = p.dirname(p.dirname(scriptPath));
  final repositoryRoot = await _gitOutput([
    "rev-parse",
    "--show-toplevel",
  ], workingDirectory: appDirectory);
  final resolvedRepositoryRoot = Directory(
    repositoryRoot,
  ).resolveSymbolicLinksSync();

  await _requireCleanWorktree(resolvedRepositoryRoot);
  final commit = await _gitOutput([
    "rev-parse",
    "HEAD",
  ], workingDirectory: resolvedRepositoryRoot);
  final containingOriginRefs = await _gitOutput(
    [
      "for-each-ref",
      "--contains=$commit",
      "--format=%(refname:short)",
      "refs/remotes/origin/",
    ],
    workingDirectory: resolvedRepositoryRoot,
    allowEmpty: true,
  );
  if (containingOriginRefs.isEmpty) {
    throw const ReleasePreparationException(
      "HEAD is not reachable from a local origin/* ref. Push the release "
      "commit, or fetch origin if it is already remote, before preparing.",
      exitCode: 65,
    );
  }
  final origin = await _gitOutput([
    "remote",
    "get-url",
    "origin",
  ], workingDirectory: resolvedRepositoryRoot);
  final sourceBaseUrl = normalizeGitHubSourceBaseUrl(origin);
  final sourceCommitUrl = "$sourceBaseUrl/commit/$commit";
  final sourceVersion = parsePubspecVersion(
    File(p.join(appDirectory, "pubspec.yaml")).readAsStringSync(),
  );
  final canonicalEndpoint = canonicalizeConfigurableEndpoint(options.endpoint);
  final tools = ReleaseToolPaths.fromEnvironment(options.environment);

  if (p.equals(options.outputDirectory, resolvedRepositoryRoot) ||
      p.isWithin(resolvedRepositoryRoot, options.outputDirectory)) {
    throw const ReleasePreparationException(
      "The release output directory must be outside the Git repository.",
      exitCode: 64,
    );
  }
  final outputDirectory = Directory(options.outputDirectory);
  outputDirectory.createSync(recursive: true);
  final resolvedOutputDirectory = outputDirectory.resolveSymbolicLinksSync();
  if (p.equals(resolvedOutputDirectory, resolvedRepositoryRoot) ||
      p.isWithin(resolvedRepositoryRoot, resolvedOutputDirectory)) {
    throw const ReleasePreparationException(
      "The release output directory must be outside the Git repository.",
      exitCode: 64,
    );
  }

  final buildApkPath = p.join(
    appDirectory,
    "build",
    "app",
    "outputs",
    "flutter-apk",
    "app-selfhosted-release.apk",
  );
  final buildApk = File(buildApkPath);
  if (buildApk.existsSync()) {
    buildApk.deleteSync();
  }

  stdout.writeln("Preparing release from clean commit $commit");
  stdout.writeln("Building configurable release for $canonicalEndpoint");
  final buildEnvironment = Map<String, String>.from(options.environment)
    ..remove("FIREBASE_TOKEN")
    ..remove("GOOGLE_APPLICATION_CREDENTIALS")
    ..remove("GOOGLE_CLOUD_PROJECT")
    ..remove("GCLOUD_PROJECT");
  Process buildProcess;
  try {
    buildProcess = await Process.start(
      p.join(appDirectory, "scripts", "build_self_hosted_android.sh"),
      const ["--release", "--target-platform", "android-arm,android-arm64"],
      workingDirectory: appDirectory,
      environment: buildEnvironment,
      includeParentEnvironment: false,
      mode: ProcessStartMode.inheritStdio,
    );
  } on ProcessException catch (error) {
    throw ReleasePreparationException(
      "Could not start the configurable Android build: ${error.message}",
      exitCode: 69,
    );
  }
  final buildExitCode = await buildProcess.exitCode;
  if (buildExitCode != 0) {
    throw ReleasePreparationException(
      "The configurable Android build failed with exit code $buildExitCode.",
    );
  }
  if (!buildApk.existsSync()) {
    throw const ReleasePreparationException(
      "The build succeeded without producing app-selfhosted-release.apk.",
    );
  }

  await _requireCleanWorktree(resolvedRepositoryRoot);
  final endingCommit = await _gitOutput([
    "rev-parse",
    "HEAD",
  ], workingDirectory: resolvedRepositoryRoot);
  if (endingCommit != commit) {
    throw const ReleasePreparationException(
      "HEAD changed while the release was building.",
      exitCode: 65,
    );
  }

  final audit = await auditAndroidReleaseApk(
    apkPath: buildApkPath,
    canonicalEndpoint: canonicalEndpoint,
    sourceVersion: sourceVersion,
    tools: tools,
  );
  await _requireCleanWorktree(resolvedRepositoryRoot);
  final auditedCommit = await _gitOutput([
    "rev-parse",
    "HEAD",
  ], workingDirectory: resolvedRepositoryRoot);
  if (auditedCommit != commit) {
    throw const ReleasePreparationException(
      "HEAD changed while the release was being audited.",
      exitCode: 65,
    );
  }

  return finalizePreparedRelease(
    buildApkPath: buildApkPath,
    audit: audit,
    outputDirectory: resolvedOutputDirectory,
    canonicalEndpoint: canonicalEndpoint,
    commit: commit,
    origin: origin,
    sourceCommitUrl: sourceCommitUrl,
  );
}

Future<ReleasePreparationResult> finalizePreparedRelease({
  required String buildApkPath,
  required AndroidReleaseAudit audit,
  required String outputDirectory,
  required String canonicalEndpoint,
  required String commit,
  required String origin,
  required String sourceCommitUrl,
}) async {
  final safeVersionName = audit.version.name.replaceAll(
    RegExp("[^A-Za-z0-9._-]"),
    "_",
  );
  final releaseId =
      "ente-photos-selfhosted-$safeVersionName-${audit.version.code}-${commit.substring(0, 12)}";
  final finalApkPath = p.join(outputDirectory, "$releaseId.apk");
  final finalManifestPath = p.join(outputDirectory, "$releaseId.manifest.json");
  if (File(finalApkPath).existsSync() || File(finalManifestPath).existsSync()) {
    throw ReleasePreparationException(
      "Release '$releaseId' already exists; prepared releases are never overwritten.",
      exitCode: 73,
    );
  }

  final stagingDirectory = Directory(
    p.join(outputDirectory, ".$releaseId.partial-${pid.toString()}"),
  )..createSync();
  final stagedApk = File(p.join(stagingDirectory.path, "$releaseId.apk"));
  final stagedManifest = File(
    p.join(stagingDirectory.path, "$releaseId.manifest.json"),
  );
  var finalizedApk = false;
  var finalizedManifest = false;
  try {
    File(buildApkPath).copySync(stagedApk.path);
    final stagedSha256 = await sha256File(stagedApk.path);
    if (stagedSha256 != audit.sha256) {
      throw const ReleasePreparationException(
        "The copied APK hash differs from the audited build output.",
      );
    }

    final manifest = <String, Object?>{
      "schemaVersion": releaseManifestSchemaVersion,
      "preparationTool": <String, Object?>{
        "name": preparationToolName,
        "version": preparationToolVersion,
      },
      "preparedAt": DateTime.now().toUtc().toIso8601String(),
      "releaseId": releaseId,
      "artifact": <String, Object?>{
        "fileName": p.basename(finalApkPath),
        "absolutePath": finalApkPath,
        "sha256": audit.sha256,
        "sizeBytes": audit.sizeBytes,
      },
      "source": <String, Object?>{
        "commit": commit,
        "remote": origin,
        "commitUrl": sourceCommitUrl,
        "worktreeClean": true,
      },
      "android": <String, Object?>{
        "packageName": audit.packageName,
        "versionName": audit.version.name,
        "versionCode": audit.version.code,
        "buildType": "release",
        "debuggable": audit.debuggable,
        "minSdk": audit.minSdk,
        "targetSdk": audit.targetSdk,
        "compileSdk": audit.compileSdk,
        "abis": audit.abis.toList()..sort(),
        "compiledDefaultEndpoint": canonicalEndpoint,
        "signingCertificateSha256": audit.signingCertificateSha256,
        "signatureSchemes": audit.signatureSchemes,
      },
    };
    stagedManifest.writeAsStringSync(
      const JsonEncoder.withIndent("  ").convert(manifest) + "\n",
      flush: true,
    );

    await _requireSuccessfulProcess("chmod", [
      "0444",
      stagedApk.path,
      stagedManifest.path,
    ], failureMessage: "Could not make the prepared release read-only.");
    await _requireSuccessfulProcess(
      "ln",
      [stagedApk.path, finalApkPath],
      failureMessage: "Could not finalize the prepared APK without overwrite.",
    );
    finalizedApk = true;
    await _requireSuccessfulProcess(
      "ln",
      [stagedManifest.path, finalManifestPath],
      failureMessage:
          "Could not finalize the release manifest without overwrite.",
    );
    finalizedManifest = true;
  } finally {
    if (!(finalizedApk && finalizedManifest)) {
      if (finalizedManifest && File(finalManifestPath).existsSync()) {
        File(finalManifestPath).deleteSync();
      }
      if (finalizedApk && File(finalApkPath).existsSync()) {
        File(finalApkPath).deleteSync();
      }
    }
    if (stagingDirectory.existsSync()) {
      stagingDirectory.deleteSync(recursive: true);
    }
  }

  return ReleasePreparationResult(
    apkPath: finalApkPath,
    manifestPath: finalManifestPath,
    sha256: audit.sha256,
    sourceCommitUrl: sourceCommitUrl,
  );
}

class ReleaseToolPaths {
  const ReleaseToolPaths({
    required this.aapt2,
    required this.apksigner,
    required this.unzip,
    required this.shasum,
  });

  factory ReleaseToolPaths.fromEnvironment(Map<String, String> environment) {
    final androidHome =
        environment["ANDROID_HOME"] ?? environment["ANDROID_SDK_ROOT"];
    if (androidHome == null || androidHome.isEmpty) {
      throw const ReleasePreparationException(
        "ANDROID_HOME or ANDROID_SDK_ROOT is required.",
        exitCode: 69,
      );
    }

    final buildToolsRoot = Directory(p.join(androidHome, "build-tools"));
    if (!buildToolsRoot.existsSync()) {
      throw ReleasePreparationException(
        "Android build tools were not found under ${buildToolsRoot.path}.",
        exitCode: 69,
      );
    }
    final candidates =
        buildToolsRoot
            .listSync()
            .whereType<Directory>()
            .where(
              (directory) =>
                  File(p.join(directory.path, "aapt2")).existsSync() &&
                  File(p.join(directory.path, "apksigner")).existsSync(),
            )
            .toList()
          ..sort((left, right) => right.path.compareTo(left.path));
    if (candidates.isEmpty) {
      throw const ReleasePreparationException(
        "No Android build-tools version contains both aapt2 and apksigner.",
        exitCode: 69,
      );
    }
    final selected = candidates.first.path;
    _findExecutable("chmod", environment);
    _findExecutable("ln", environment);
    return ReleaseToolPaths(
      aapt2: p.join(selected, "aapt2"),
      apksigner: p.join(selected, "apksigner"),
      unzip: _findExecutable("unzip", environment),
      shasum: _findExecutable("shasum", environment),
    );
  }

  final String aapt2;
  final String apksigner;
  final String unzip;
  final String shasum;
}

String _findExecutable(String name, Map<String, String> environment) {
  final pathValue = environment["PATH"] ?? "";
  for (final directory in pathValue.split(Platform.isWindows ? ";" : ":")) {
    if (directory.isEmpty) {
      continue;
    }
    final candidate = File(p.join(directory, name));
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }
  throw ReleasePreparationException(
    "Required command '$name' was not found on PATH.",
    exitCode: 69,
  );
}

Future<AndroidReleaseAudit> auditAndroidReleaseApk({
  required String apkPath,
  required String canonicalEndpoint,
  required ReleaseVersion sourceVersion,
  required ReleaseToolPaths tools,
  Map<String, String>? processEnvironment,
}) async {
  final apk = File(apkPath);
  if (!apk.existsSync()) {
    throw ReleasePreparationException("APK does not exist: $apkPath");
  }

  final badgingResult = await _requireSuccessfulProcess(
    tools.aapt2,
    ["dump", "badging", apkPath],
    environment: processEnvironment,
    failureMessage: "aapt2 could not inspect the APK metadata.",
  );
  final badging = parseAaptBadging(badgingResult.stdout as String);
  if (badging.packageName != expectedPackageName) {
    throw ReleasePreparationException(
      "Expected package $expectedPackageName, found ${badging.packageName}.",
    );
  }
  if (badging.version.name != sourceVersion.name ||
      badging.version.code != sourceVersion.code) {
    throw ReleasePreparationException(
      "APK version ${badging.version.name}+${badging.version.code} does not "
      "match pubspec ${sourceVersion.name}+${sourceVersion.code}.",
    );
  }
  if (badging.minSdk != expectedMinSdk ||
      badging.targetSdk != expectedTargetSdk ||
      badging.compileSdk != expectedCompileSdk) {
    throw ReleasePreparationException(
      "Expected SDKs min/target/compile "
      "$expectedMinSdk/$expectedTargetSdk/$expectedCompileSdk, found "
      "${badging.minSdk}/${badging.targetSdk}/${badging.compileSdk}.",
    );
  }
  if (!_sameSet(badging.abis, expectedAbis)) {
    throw ReleasePreparationException(
      "Expected APK ABIs ${_sorted(expectedAbis)}, found "
      "${_sorted(badging.abis)}.",
    );
  }

  final manifestResult = await _requireSuccessfulProcess(
    tools.aapt2,
    ["dump", "xmltree", apkPath, "--file", "AndroidManifest.xml"],
    environment: processEnvironment,
    failureMessage: "aapt2 could not inspect AndroidManifest.xml.",
  );
  final debuggable = manifestIsDebuggable(manifestResult.stdout as String);
  if (debuggable || badging.packageName.endsWith(".debug")) {
    throw const ReleasePreparationException(
      "The APK is debuggable or uses a debug package suffix.",
    );
  }

  final signerResult = await _requireSuccessfulProcess(
    tools.apksigner,
    ["verify", "--verbose", "--print-certs", apkPath],
    environment: processEnvironment,
    failureMessage: "apksigner rejected the APK.",
  );
  final signer = parseApkSignerOutput(signerResult.stdout as String);
  validateApkSignerAudit(signer);

  await _requireSuccessfulProcess(
    tools.unzip,
    ["-tq", apkPath],
    environment: processEnvironment,
    failureMessage: "The APK ZIP archive failed its integrity check.",
  );
  final entriesResult = await _requireSuccessfulProcess(
    tools.unzip,
    ["-Z1", apkPath],
    environment: processEnvironment,
    failureMessage: "The APK ZIP entries could not be listed.",
  );
  final zipAbis = <String>{};
  for (final line in const LineSplitter().convert(
    entriesResult.stdout as String,
  )) {
    final match = RegExp(r"^lib/([^/]+)/[^/]+$").firstMatch(line);
    if (match != null) {
      zipAbis.add(match.group(1)!);
    }
  }
  if (!_sameSet(zipAbis, expectedAbis)) {
    throw ReleasePreparationException(
      "Expected ZIP ABIs ${_sorted(expectedAbis)}, found ${_sorted(zipAbis)}.",
    );
  }

  final appLibraryResult = await Process.run(
    tools.unzip,
    ["-p", apkPath, "lib/arm64-v8a/libapp.so"],
    environment: processEnvironment,
    stdoutEncoding: null,
    stderrEncoding: utf8,
  );
  if (appLibraryResult.exitCode != 0 || appLibraryResult.stdout is! List<int>) {
    throw const ReleasePreparationException(
      "Could not extract the ARM64 Flutter application library.",
    );
  }
  final endpointBytes = utf8.encode(canonicalEndpoint);
  if (!containsBytes(appLibraryResult.stdout as List<int>, endpointBytes)) {
    throw ReleasePreparationException(
      "The compiled ARM64 application does not contain $canonicalEndpoint.",
    );
  }

  return AndroidReleaseAudit(
    packageName: badging.packageName,
    version: badging.version,
    minSdk: badging.minSdk,
    targetSdk: badging.targetSdk,
    compileSdk: badging.compileSdk,
    abis: badging.abis,
    debuggable: false,
    signingCertificateSha256: signer.certificateSha256,
    signatureSchemes: signer.signatureSchemes,
    sha256: await sha256File(
      apkPath,
      shasum: tools.shasum,
      environment: processEnvironment,
    ),
    sizeBytes: apk.lengthSync(),
  );
}

AaptBadging parseAaptBadging(String output) {
  final packageMatch = RegExp(
    r"package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'"
    r".*compileSdkVersion='([0-9]+)'",
  ).firstMatch(output);
  final minSdkMatch = RegExp(
    r"^minSdkVersion:'([0-9]+)'$",
    multiLine: true,
  ).firstMatch(output);
  final targetSdkMatch = RegExp(
    r"^targetSdkVersion:'([0-9]+)'$",
    multiLine: true,
  ).firstMatch(output);
  final nativeCodeMatch = RegExp(
    r"^native-code:(.*)$",
    multiLine: true,
  ).firstMatch(output);
  if (packageMatch == null ||
      minSdkMatch == null ||
      targetSdkMatch == null ||
      nativeCodeMatch == null) {
    throw const ReleasePreparationException(
      "aapt2 output is missing required release metadata.",
    );
  }
  final abis = RegExp("'([^']+)'")
      .allMatches(nativeCodeMatch.group(1)!)
      .map((match) => match.group(1)!)
      .toSet();
  return AaptBadging(
    packageName: packageMatch.group(1)!,
    version: ReleaseVersion(
      packageMatch.group(3)!,
      int.parse(packageMatch.group(2)!),
    ),
    minSdk: int.parse(minSdkMatch.group(1)!),
    targetSdk: int.parse(targetSdkMatch.group(1)!),
    compileSdk: int.parse(packageMatch.group(4)!),
    abis: abis,
  );
}

ApkSignerAudit parseApkSignerOutput(String output) {
  final certificateMatch = RegExp(
    r"^Signer #1 certificate SHA-256 digest: ([0-9a-fA-F:]+)$",
    multiLine: true,
  ).firstMatch(output);
  final signerCountMatch = RegExp(
    r"^Number of signers: ([0-9]+)$",
    multiLine: true,
  ).firstMatch(output);
  if (certificateMatch == null || signerCountMatch == null) {
    throw const ReleasePreparationException(
      "apksigner output is missing signer metadata.",
    );
  }
  final schemes = <String, bool>{};
  final schemePattern = RegExp(
    r"^Verified using (v[0-9.]+) scheme(?: \([^)]*\))?: (true|false)$",
    multiLine: true,
  );
  for (final match in schemePattern.allMatches(output)) {
    schemes[match.group(1)!] = match.group(2) == "true";
  }
  return ApkSignerAudit(
    certificateSha256: certificateMatch
        .group(1)!
        .replaceAll(":", "")
        .toLowerCase(),
    signerCount: int.parse(signerCountMatch.group(1)!),
    signatureSchemes: schemes,
  );
}

void validateApkSignerAudit(ApkSignerAudit signer) {
  if (signer.signerCount != 1) {
    throw ReleasePreparationException(
      "Expected one APK signer, found ${signer.signerCount}.",
    );
  }
  if (signer.certificateSha256 != expectedSigningCertificateSha256) {
    throw ReleasePreparationException(
      "Signing certificate mismatch: ${signer.certificateSha256}.",
    );
  }
  if (signer.signatureSchemes["v2"] != true) {
    throw const ReleasePreparationException(
      "APK Signature Scheme v2 verification did not pass.",
    );
  }
}

ReleaseVersion parsePubspecVersion(String pubspec) {
  final match = RegExp(
    r"^version:\s*([^\s+]+)\+([0-9]+)\s*$",
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw const ReleasePreparationException(
      "pubspec.yaml must contain version: <name>+<positive code>.",
      exitCode: 65,
    );
  }
  final code = int.parse(match.group(2)!);
  if (code <= 0) {
    throw const ReleasePreparationException(
      "The pubspec version code must be positive.",
      exitCode: 65,
    );
  }
  return ReleaseVersion(match.group(1)!, code);
}

String canonicalizeConfigurableEndpoint(String endpoint) {
  try {
    return EndpointPolicy(
      mode: EndpointMode.configurable,
      compiledEndpoint: endpoint,
    ).configurableDefaultEndpoint;
  } on EndpointPolicyException catch (error) {
    throw ReleasePreparationException(
      "Invalid ENTE_SELF_HOSTED_ENDPOINT: ${error.message}",
      exitCode: 64,
    );
  }
}

bool manifestIsDebuggable(String xmlTree) {
  return const LineSplitter()
      .convert(xmlTree)
      .any(
        (line) =>
            line.contains("android:debuggable") &&
            (line.contains("0xffffffff") ||
                line.toLowerCase().contains("true")),
      );
}

String normalizeGitHubSourceBaseUrl(String remote) {
  var value = remote.trim();
  if (value.startsWith("git@github.com:")) {
    value = "https://github.com/${value.substring("git@github.com:".length)}";
  } else if (value.startsWith("ssh://git@github.com/")) {
    value =
        "https://github.com/${value.substring("ssh://git@github.com/".length)}";
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != "https" ||
      uri.host.toLowerCase() != "github.com" ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw ReleasePreparationException(
      "origin must be an HTTPS or SSH GitHub repository URL, found '$remote'.",
      exitCode: 65,
    );
  }
  var path = uri.path.replaceFirst(RegExp(r"/+$"), "");
  if (path.endsWith(".git")) {
    path = path.substring(0, path.length - 4);
  }
  final segments = path.split("/").where((segment) => segment.isNotEmpty);
  if (segments.length != 2) {
    throw ReleasePreparationException(
      "origin must identify one GitHub owner and repository, found '$remote'.",
      exitCode: 65,
    );
  }
  return "https://github.com$path";
}

bool containsBytes(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) {
    return true;
  }
  var start = 0;
  while (start <= haystack.length - needle.length) {
    final candidate = haystack.indexOf(needle.first, start);
    if (candidate < 0 || candidate > haystack.length - needle.length) {
      return false;
    }
    var matches = true;
    for (var index = 1; index < needle.length; index++) {
      if (haystack[candidate + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
    start = candidate + 1;
  }
  return false;
}

Future<String> sha256File(
  String path, {
  String shasum = "shasum",
  Map<String, String>? environment,
}) async {
  final result = await _requireSuccessfulProcess(
    shasum,
    ["-a", "256", path],
    environment: environment,
    failureMessage: "Could not calculate the APK SHA-256.",
  );
  final match = RegExp(
    r"^([0-9a-fA-F]{64})\s",
  ).firstMatch((result.stdout as String).trim());
  if (match == null) {
    throw const ReleasePreparationException(
      "shasum returned an unexpected SHA-256 format.",
    );
  }
  return match.group(1)!.toLowerCase();
}

Future<void> _requireCleanWorktree(String repositoryRoot) async {
  final status = await _gitOutput(
    ["status", "--porcelain", "--untracked-files=normal"],
    workingDirectory: repositoryRoot,
    allowEmpty: true,
  );
  if (status.isNotEmpty) {
    throw ReleasePreparationException(
      "Git worktree is not clean:\n$status",
      exitCode: 65,
    );
  }
}

Future<String> _gitOutput(
  List<String> arguments, {
  required String workingDirectory,
  bool allowEmpty = false,
}) async {
  final result = await _requireSuccessfulProcess(
    "git",
    arguments,
    workingDirectory: workingDirectory,
    failureMessage: "Git command failed: git ${arguments.join(" ")}",
  );
  final output = (result.stdout as String).trim();
  if (!allowEmpty && output.isEmpty) {
    throw ReleasePreparationException(
      "Git command returned no output: git ${arguments.join(" ")}",
      exitCode: 65,
    );
  }
  return output;
}

Future<ProcessResult> _requireSuccessfulProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  required String failureMessage,
}) async {
  ProcessResult result;
  try {
    result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException catch (error) {
    throw ReleasePreparationException(
      "$failureMessage ${error.message}",
      exitCode: 69,
    );
  }
  if (result.exitCode != 0) {
    final details = (result.stderr as String).trim();
    throw ReleasePreparationException(
      details.isEmpty ? failureMessage : "$failureMessage\n$details",
    );
  }
  return result;
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

String _sorted(Set<String> values) {
  final sorted = values.toList()..sort();
  return sorted.join(", ");
}
