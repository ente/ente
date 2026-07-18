import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;
import "package:photos/core/network/endpoint_policy.dart";

const preparationToolName = "ente-self-hosted-ios-release-preparer";
const preparationToolVersion = "1.0.0";
const releaseManifestSchemaVersion = 1;
const archiveExportContractVersion = 1;

const expectedBundleIdentifier = "me.vanton.ente.photos.selfhosted";
const expectedDistributionCertificateSha256 =
    "8fcaf5f761acbcbeeae4710fb75370646071d8a905ac2a70ffeb46676c4a1e0c";
const expectedArchitectures = <String>{"arm64"};
const expectedSignedEntitlementKeys = <String>{
  "application-identifier",
  "com.apple.developer.team-identifier",
  "get-task-allow",
};
const expectedProfileEntitlementKeys = <String>{
  "application-identifier",
  "com.apple.developer.team-identifier",
  "get-task-allow",
  "keychain-access-groups",
};

const _usage = """
Prepare and independently audit a configurable Ente Photos iOS Ad Hoc release.

Usage:
  ./scripts/prepare_self_hosted_ios_release.sh \\
    --output-dir /absolute/path/outside/the/repository

Required environment:
  ENTE_SELF_HOSTED_ENDPOINT          Canonicalizable HTTPS Museum origin.
  ENTE_IOS_DISTRIBUTION_TEAM         Ten-character Apple Team ID.
  ENTE_IOS_ADHOC_PROFILE             Absolute private .mobileprovision path.
  ENTE_IOS_EXPECTED_DEVICE_COUNT     Positive authorized-device count.
  ENTE_IOS_MARKETING_VERSION         One to three numeric components.
  ENTE_IOS_BUILD_NUMBER              Positive integer CFBundleVersion.

The command builds from a detached worktree at the pushed HEAD commit. It owns
temporary archive/export paths and writes only a read-only IPA/manifest pair to
the requested output directory. It never invokes Firebase.
""";

Future<void> main(List<String> arguments) async {
  try {
    final options = IOSPreparationOptions.parse(
      arguments,
      environment: Platform.environment,
    );
    if (options.showHelp) {
      stdout.write(_usage);
      return;
    }

    final result = await prepareSelfHostedIOSRelease(options);
    stdout.writeln();
    stdout.writeln("Prepared audited iOS release:");
    stdout.writeln("  IPA: ${result.ipaPath}");
    stdout.writeln("  Manifest: ${result.manifestPath}");
    stdout.writeln("  SHA-256: ${result.sha256}");
    stdout.writeln("  Source: ${result.sourceCommitUrl}");
  } on IOSReleasePreparationException catch (error) {
    stderr.writeln("iOS release preparation failed: ${error.message}");
    exitCode = error.exitCode;
  } on Object catch (error) {
    stderr.writeln("iOS release preparation failed unexpectedly: $error");
    exitCode = 70;
  }
}

class IOSPreparationOptions {
  IOSPreparationOptions({
    required this.outputDirectory,
    required this.endpoint,
    required this.distributionTeam,
    required this.profilePath,
    required this.expectedDeviceCount,
    required this.marketingVersion,
    required this.buildNumber,
    required this.environment,
    this.showHelp = false,
  });

  factory IOSPreparationOptions.parse(
    List<String> arguments, {
    required Map<String, String> environment,
  }) {
    if (arguments.length == 1 &&
        (arguments.single == "--help" || arguments.single == "-h")) {
      return IOSPreparationOptions(
        outputDirectory: "",
        endpoint: "",
        distributionTeam: "",
        profilePath: "",
        expectedDeviceCount: 0,
        marketingVersion: "",
        buildNumber: 0,
        environment: environment,
        showHelp: true,
      );
    }

    String? outputDirectory;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == "--output-dir") {
        if (index + 1 >= arguments.length) {
          throw const IOSReleasePreparationException(
            "--output-dir requires a value.",
            exitCode: 64,
          );
        }
        outputDirectory = arguments[++index];
      } else if (argument.startsWith("--output-dir=")) {
        outputDirectory = argument.substring("--output-dir=".length);
      } else {
        throw IOSReleasePreparationException(
          "Unknown argument '$argument'.\n\n$_usage",
          exitCode: 64,
        );
      }
    }

    outputDirectory ??= environment["ENTE_IOS_RELEASE_OUTPUT_DIR"];
    final endpoint = _requiredEnvironment(
      environment,
      "ENTE_SELF_HOSTED_ENDPOINT",
    );
    final distributionTeam = _requiredEnvironment(
      environment,
      "ENTE_IOS_DISTRIBUTION_TEAM",
    );
    final profilePath = _requiredEnvironment(
      environment,
      "ENTE_IOS_ADHOC_PROFILE",
    );
    final deviceCountValue = _requiredEnvironment(
      environment,
      "ENTE_IOS_EXPECTED_DEVICE_COUNT",
    );
    final marketingVersion = _requiredEnvironment(
      environment,
      "ENTE_IOS_MARKETING_VERSION",
    );
    final buildNumberValue = _requiredEnvironment(
      environment,
      "ENTE_IOS_BUILD_NUMBER",
    );

    if (outputDirectory == null || outputDirectory.trim().isEmpty) {
      throw const IOSReleasePreparationException(
        "Provide --output-dir or ENTE_IOS_RELEASE_OUTPUT_DIR.",
        exitCode: 64,
      );
    }
    if (!p.isAbsolute(outputDirectory)) {
      throw const IOSReleasePreparationException(
        "The iOS release output directory must be an absolute path.",
        exitCode: 64,
      );
    }
    if (!RegExp(r"^[A-Z0-9]{10}$").hasMatch(distributionTeam)) {
      throw const IOSReleasePreparationException(
        "ENTE_IOS_DISTRIBUTION_TEAM must be a ten-character Apple Team ID.",
        exitCode: 64,
      );
    }
    if (!p.isAbsolute(profilePath) ||
        !profilePath.endsWith(".mobileprovision")) {
      throw const IOSReleasePreparationException(
        "ENTE_IOS_ADHOC_PROFILE must be an absolute .mobileprovision path.",
        exitCode: 64,
      );
    }
    final expectedDeviceCount = int.tryParse(deviceCountValue);
    if (expectedDeviceCount == null || expectedDeviceCount <= 0) {
      throw const IOSReleasePreparationException(
        "ENTE_IOS_EXPECTED_DEVICE_COUNT must be a positive integer.",
        exitCode: 64,
      );
    }
    if (!RegExp(r"^[0-9]+(?:\.[0-9]+){0,2}$").hasMatch(marketingVersion)) {
      throw const IOSReleasePreparationException(
        "ENTE_IOS_MARKETING_VERSION must contain one to three numeric components.",
        exitCode: 64,
      );
    }
    final buildNumber = int.tryParse(buildNumberValue);
    if (buildNumber == null || buildNumber <= 0) {
      throw const IOSReleasePreparationException(
        "ENTE_IOS_BUILD_NUMBER must be a positive integer.",
        exitCode: 64,
      );
    }

    return IOSPreparationOptions(
      outputDirectory: p.normalize(outputDirectory),
      endpoint: endpoint,
      distributionTeam: distributionTeam,
      profilePath: p.normalize(profilePath),
      expectedDeviceCount: expectedDeviceCount,
      marketingVersion: marketingVersion,
      buildNumber: buildNumber,
      environment: environment,
    );
  }

  final String outputDirectory;
  final String endpoint;
  final String distributionTeam;
  final String profilePath;
  final int expectedDeviceCount;
  final String marketingVersion;
  final int buildNumber;
  final Map<String, String> environment;
  final bool showHelp;
}

class IOSReleasePreparationResult {
  const IOSReleasePreparationResult({
    required this.ipaPath,
    required this.manifestPath,
    required this.sha256,
    required this.sourceCommitUrl,
  });

  final String ipaPath;
  final String manifestPath;
  final String sha256;
  final String sourceCommitUrl;
}

class IOSReleasePreparationException implements Exception {
  const IOSReleasePreparationException(this.message, {this.exitCode = 66});

  final String message;
  final int exitCode;

  @override
  String toString() => message;
}

class XcodeVersion {
  const XcodeVersion({required this.version, required this.buildVersion});

  final String version;
  final String buildVersion;
}

class IOSReleaseAudit {
  const IOSReleaseAudit({
    required this.bundleIdentifier,
    required this.marketingVersion,
    required this.buildNumber,
    required this.compiledDefaultEndpoint,
    required this.architectures,
    required this.machOCount,
    required this.debuggable,
    required this.extensionCount,
    required this.signedEntitlementKeys,
    required this.applicationIdentifier,
    required this.teamIdentifier,
    required this.profileName,
    required this.profileUuid,
    required this.profileExpiration,
    required this.authorizedDeviceCount,
    required this.signingCertificateSha256,
    required this.certificateNotBefore,
    required this.certificateNotAfter,
    required this.deepSignatureStructureValid,
    required this.localTrustChainAccepted,
    required this.sha256,
    required this.sizeBytes,
  });

  final String bundleIdentifier;
  final String marketingVersion;
  final int buildNumber;
  final String compiledDefaultEndpoint;
  final Set<String> architectures;
  final int machOCount;
  final bool debuggable;
  final int extensionCount;
  final Set<String> signedEntitlementKeys;
  final String applicationIdentifier;
  final String teamIdentifier;
  final String profileName;
  final String profileUuid;
  final DateTime profileExpiration;
  final int authorizedDeviceCount;
  final String signingCertificateSha256;
  final DateTime certificateNotBefore;
  final DateTime certificateNotAfter;
  final bool deepSignatureStructureValid;
  final bool localTrustChainAccepted;
  final String sha256;
  final int sizeBytes;
}

class IOSReleaseToolPaths {
  const IOSReleaseToolPaths({
    required this.unzip,
    required this.plutil,
    required this.security,
    required this.codesign,
    required this.openssl,
    required this.shasum,
    required this.file,
    required this.lipo,
    required this.xcodebuild,
  });

  factory IOSReleaseToolPaths.fromEnvironment(Map<String, String> environment) {
    String resolve(String environmentName, String fallback) {
      final configured = environment[environmentName];
      if (configured != null && configured.isNotEmpty) {
        if (!p.isAbsolute(configured) || !File(configured).existsSync()) {
          throw IOSReleasePreparationException(
            "$environmentName must name an existing absolute executable.",
            exitCode: 69,
          );
        }
        return configured;
      }
      return _findExecutable(fallback, environment);
    }

    _findExecutable("chmod", environment);
    _findExecutable("ln", environment);
    return IOSReleaseToolPaths(
      unzip: resolve("UNZIP_BIN", "unzip"),
      plutil: resolve("PLUTIL_BIN", "plutil"),
      security: resolve("SECURITY_BIN", "security"),
      codesign: resolve("CODESIGN_BIN", "codesign"),
      openssl: resolve("OPENSSL_BIN", "openssl"),
      shasum: resolve("SHASUM_BIN", "shasum"),
      file: resolve("FILE_BIN", "file"),
      lipo: resolve("LIPO_BIN", "lipo"),
      xcodebuild: resolve("XCODEBUILD_BIN", "xcodebuild"),
    );
  }

  final String unzip;
  final String plutil;
  final String security;
  final String codesign;
  final String openssl;
  final String shasum;
  final String file;
  final String lipo;
  final String xcodebuild;
}

typedef IOSIpaAuditor =
    Future<IOSReleaseAudit> Function({
      required String ipaPath,
      required String canonicalEndpoint,
      required String expectedTeam,
      required int expectedDeviceCount,
      required String expectedMarketingVersion,
      required int expectedBuildNumber,
      required IOSReleaseToolPaths tools,
      Map<String, String>? processEnvironment,
    });

Future<IOSReleasePreparationResult> prepareSelfHostedIOSRelease(
  IOSPreparationOptions options, {
  String? appDirectoryOverride,
  IOSIpaAuditor auditor = auditIOSReleaseIpa,
}) async {
  final appDirectory = appDirectoryOverride == null
      ? p.dirname(p.dirname(p.normalize(Platform.script.toFilePath())))
      : p.normalize(appDirectoryOverride);
  final repositoryRoot = await _gitOutput([
    "rev-parse",
    "--show-toplevel",
  ], workingDirectory: appDirectory);
  final resolvedRepositoryRoot = Directory(
    repositoryRoot,
  ).resolveSymbolicLinksSync();
  final commit = await _gitOutput([
    "rev-parse",
    "HEAD",
  ], workingDirectory: resolvedRepositoryRoot);
  if (!RegExp(r"^[0-9a-f]{40}$").hasMatch(commit)) {
    throw const IOSReleasePreparationException(
      "HEAD must resolve to one full Git commit.",
      exitCode: 65,
    );
  }
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
    throw const IOSReleasePreparationException(
      "HEAD is not reachable from a local origin/* ref. Push the release "
      "commit, or fetch origin if it is already remote, before preparing.",
      exitCode: 65,
    );
  }

  const criticalPaths = <String>[
    "mobile/apps/photos/scripts/build_self_hosted_ios.sh",
    "mobile/apps/photos/scripts/prepare_self_hosted_ios_release.dart",
    "mobile/apps/photos/scripts/prepare_self_hosted_ios_release.sh",
  ];
  for (final path in criticalPaths) {
    await _requireTrackedPathMatchesCommit(
      resolvedRepositoryRoot,
      commit,
      path,
    );
  }

  final origin = await _gitOutput([
    "remote",
    "get-url",
    "origin",
  ], workingDirectory: resolvedRepositoryRoot);
  final sourceBaseUrl = normalizeGitHubSourceBaseUrl(origin);
  final sourceCommitUrl = "$sourceBaseUrl/commit/$commit";
  final canonicalEndpoint = canonicalizeConfigurableEndpoint(options.endpoint);
  final profilePath = _resolvePrivateProfile(
    options.profilePath,
    resolvedRepositoryRoot,
  );
  final outputDirectory = _resolveExternalOutputDirectory(
    options.outputDirectory,
    resolvedRepositoryRoot,
  );
  final tools = IOSReleaseToolPaths.fromEnvironment(options.environment);
  final xcodeVersion = await readXcodeVersion(
    tools.xcodebuild,
    environment: options.environment,
  );
  final preparationSourceSha256 = await sha256File(
    p.join(appDirectory, "scripts", "prepare_self_hosted_ios_release.dart"),
    shasum: tools.shasum,
    environment: options.environment,
  );

  final workRoot = Directory.systemTemp.createTempSync(
    "ente-ios-release-preparation-",
  );
  final checkoutDirectory = p.join(workRoot.path, "checkout");
  final buildOutputDirectory = Directory(p.join(workRoot.path, "build-output"))
    ..createSync();
  final archivePath = p.join(buildOutputDirectory.path, "release.xcarchive");
  final exportPath = p.join(buildOutputDirectory.path, "export");
  var worktreeAdded = false;
  try {
    await _requireSuccessfulProcess(
      "git",
      ["worktree", "add", "--detach", checkoutDirectory, commit],
      workingDirectory: resolvedRepositoryRoot,
      failureMessage: "Could not create the detached release worktree.",
    );
    worktreeAdded = true;
    await _requireCleanCheckout(checkoutDirectory, expectedCommit: commit);

    final checkoutAppDirectory = p.join(
      checkoutDirectory,
      "mobile",
      "apps",
      "photos",
    );
    final sourceMarketingVersion = parsePubspecMarketingVersion(
      File(p.join(checkoutAppDirectory, "pubspec.yaml")).readAsStringSync(),
    );
    if (sourceMarketingVersion != options.marketingVersion) {
      throw IOSReleasePreparationException(
        "Requested marketing version ${options.marketingVersion} does not "
        "match committed pubspec version $sourceMarketingVersion.",
        exitCode: 65,
      );
    }
    final builderPath = p.join(
      checkoutAppDirectory,
      "scripts",
      "build_self_hosted_ios.sh",
    );
    if (!File(builderPath).existsSync()) {
      throw const IOSReleasePreparationException(
        "The detached release checkout has no guarded iOS build wrapper.",
        exitCode: 65,
      );
    }

    final buildEnvironment =
        sanitizedIOSPreparationEnvironment(options.environment)
          ..["ENTE_SELF_HOSTED_ENDPOINT"] = canonicalEndpoint
          ..["ENTE_IOS_DISTRIBUTION_TEAM"] = options.distributionTeam
          ..["ENTE_IOS_ADHOC_PROFILE"] = profilePath
          ..["ENTE_IOS_EXPECTED_DEVICE_COUNT"] = options.expectedDeviceCount
              .toString()
          ..["ENTE_IOS_MARKETING_VERSION"] = options.marketingVersion
          ..["ENTE_IOS_BUILD_NUMBER"] = options.buildNumber.toString()
          ..["ENTE_IOS_ARCHIVE_PATH"] = archivePath
          ..["ENTE_IOS_EXPORT_PATH"] = exportPath;

    stdout.writeln("Preparing iOS release from pushed commit $commit");
    stdout.writeln(
      "Building the isolated configurable release for $canonicalEndpoint",
    );
    Process buildProcess;
    try {
      buildProcess = await Process.start(
        builderPath,
        const ["--adhoc"],
        workingDirectory: checkoutAppDirectory,
        environment: buildEnvironment,
        includeParentEnvironment: false,
        mode: ProcessStartMode.inheritStdio,
      );
    } on ProcessException catch (error) {
      throw IOSReleasePreparationException(
        "Could not start the guarded iOS build: ${error.message}",
        exitCode: 69,
      );
    }
    final buildExitCode = await buildProcess.exitCode;
    if (buildExitCode != 0) {
      throw IOSReleasePreparationException(
        "The guarded iOS build failed with exit code $buildExitCode.",
      );
    }

    final exportedIpas = Directory(exportPath)
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith(".ipa"))
        .toList();
    if (exportedIpas.length != 1) {
      throw const IOSReleasePreparationException(
        "The guarded export must produce exactly one IPA.",
      );
    }
    await _requireCleanCheckout(checkoutDirectory, expectedCommit: commit);

    final audit = await auditor(
      ipaPath: exportedIpas.single.path,
      canonicalEndpoint: canonicalEndpoint,
      expectedTeam: options.distributionTeam,
      expectedDeviceCount: options.expectedDeviceCount,
      expectedMarketingVersion: options.marketingVersion,
      expectedBuildNumber: options.buildNumber,
      tools: tools,
      processEnvironment: buildEnvironment,
    );
    await _requireCleanCheckout(checkoutDirectory, expectedCommit: commit);

    return finalizePreparedIOSRelease(
      buildIpaPath: exportedIpas.single.path,
      audit: audit,
      outputDirectory: outputDirectory,
      commit: commit,
      origin: origin,
      sourceCommitUrl: sourceCommitUrl,
      preparationSourceSha256: preparationSourceSha256,
      xcodeVersion: xcodeVersion,
    );
  } finally {
    await _cleanupDetachedWorktree(
      repositoryRoot: resolvedRepositoryRoot,
      checkoutDirectory: checkoutDirectory,
      workRoot: workRoot,
      worktreeAdded: worktreeAdded,
    );
  }
}

Future<IOSReleasePreparationResult> finalizePreparedIOSRelease({
  required String buildIpaPath,
  required IOSReleaseAudit audit,
  required String outputDirectory,
  required String commit,
  required String origin,
  required String sourceCommitUrl,
  required String preparationSourceSha256,
  required XcodeVersion xcodeVersion,
}) async {
  final safeVersion = audit.marketingVersion.replaceAll(
    RegExp("[^A-Za-z0-9._-]"),
    "_",
  );
  final releaseId =
      "ente-photos-selfhosted-ios-$safeVersion-${audit.buildNumber}-${commit.substring(0, 12)}";
  final finalIpaPath = p.join(outputDirectory, "$releaseId.ipa");
  final finalManifestPath = p.join(outputDirectory, "$releaseId.manifest.json");
  if (File(finalIpaPath).existsSync() || File(finalManifestPath).existsSync()) {
    throw IOSReleasePreparationException(
      "Release '$releaseId' already exists; prepared releases are never overwritten.",
      exitCode: 73,
    );
  }

  final stagingDirectory = Directory(
    p.join(outputDirectory, ".$releaseId.partial-$pid"),
  )..createSync();
  final stagedIpa = File(p.join(stagingDirectory.path, "$releaseId.ipa"));
  final stagedManifest = File(
    p.join(stagingDirectory.path, "$releaseId.manifest.json"),
  );
  var finalizedIpa = false;
  var finalizedManifest = false;
  try {
    File(buildIpaPath).copySync(stagedIpa.path);
    final stagedSha256 = await sha256File(stagedIpa.path);
    if (stagedSha256 != audit.sha256) {
      throw const IOSReleasePreparationException(
        "The copied IPA hash differs from the independently audited export.",
      );
    }

    final manifest = <String, Object?>{
      "schemaVersion": releaseManifestSchemaVersion,
      "preparationTool": <String, Object?>{
        "name": preparationToolName,
        "version": preparationToolVersion,
        "sourceSha256": preparationSourceSha256,
      },
      "preparedAt": DateTime.now().toUtc().toIso8601String(),
      "releaseId": releaseId,
      "artifact": <String, Object?>{
        "fileName": p.basename(finalIpaPath),
        "absolutePath": finalIpaPath,
        "sha256": audit.sha256,
        "sizeBytes": audit.sizeBytes,
      },
      "source": <String, Object?>{
        "commit": commit,
        "remote": origin,
        "commitUrl": sourceCommitUrl,
        "isolatedCheckout": true,
        "checkoutCleanBeforeBuild": true,
        "checkoutCleanAfterAudit": true,
      },
      "build": <String, Object?>{
        "archiveExportContractVersion": archiveExportContractVersion,
        "scheme": "selfhosted",
        "configuration": "Release-selfhosted",
        "exportMethod": "release-testing",
        "xcodeVersion": xcodeVersion.version,
        "xcodeBuildVersion": xcodeVersion.buildVersion,
      },
      "ios": <String, Object?>{
        "bundleIdentifier": audit.bundleIdentifier,
        "marketingVersion": audit.marketingVersion,
        "buildNumber": audit.buildNumber,
        "buildConfiguration": "release",
        "debuggable": audit.debuggable,
        "compiledDefaultEndpoint": audit.compiledDefaultEndpoint,
        "architectures": audit.architectures.toList()..sort(),
        "machOCount": audit.machOCount,
        "extensionCount": audit.extensionCount,
        "signedEntitlementKeys": audit.signedEntitlementKeys.toList()..sort(),
        "applicationIdentifier": audit.applicationIdentifier,
        "teamIdentifier": audit.teamIdentifier,
        "profile": <String, Object?>{
          "name": audit.profileName,
          "uuid": audit.profileUuid,
          "expiresAt": audit.profileExpiration.toUtc().toIso8601String(),
          "authorizedDeviceCount": audit.authorizedDeviceCount,
        },
        "signingCertificate": <String, Object?>{
          "sha256": audit.signingCertificateSha256,
          "notBefore": audit.certificateNotBefore.toUtc().toIso8601String(),
          "notAfter": audit.certificateNotAfter.toUtc().toIso8601String(),
        },
        "signature": <String, Object?>{
          "deepStructureValid": audit.deepSignatureStructureValid,
          "localTrustChainAccepted": audit.localTrustChainAccepted,
        },
      },
    };
    stagedManifest.writeAsStringSync(
      const JsonEncoder.withIndent("  ").convert(manifest) + "\n",
      flush: true,
    );

    await _requireSuccessfulProcess(
      "chmod",
      ["0444", stagedIpa.path, stagedManifest.path],
      failureMessage: "Could not make the prepared iOS release read-only.",
    );
    await _requireSuccessfulProcess(
      "ln",
      [stagedIpa.path, finalIpaPath],
      failureMessage: "Could not finalize the prepared IPA without overwrite.",
    );
    finalizedIpa = true;
    await _requireSuccessfulProcess(
      "ln",
      [stagedManifest.path, finalManifestPath],
      failureMessage:
          "Could not finalize the iOS release manifest without overwrite.",
    );
    finalizedManifest = true;
  } finally {
    if (!(finalizedIpa && finalizedManifest)) {
      if (finalizedManifest && File(finalManifestPath).existsSync()) {
        File(finalManifestPath).deleteSync();
      }
      if (finalizedIpa && File(finalIpaPath).existsSync()) {
        File(finalIpaPath).deleteSync();
      }
    }
    if (stagingDirectory.existsSync()) {
      stagingDirectory.deleteSync(recursive: true);
    }
  }

  return IOSReleasePreparationResult(
    ipaPath: finalIpaPath,
    manifestPath: finalManifestPath,
    sha256: audit.sha256,
    sourceCommitUrl: sourceCommitUrl,
  );
}

Future<IOSReleaseAudit> auditIOSReleaseIpa({
  required String ipaPath,
  required String canonicalEndpoint,
  required String expectedTeam,
  required int expectedDeviceCount,
  required String expectedMarketingVersion,
  required int expectedBuildNumber,
  required IOSReleaseToolPaths tools,
  Map<String, String>? processEnvironment,
}) async {
  final ipa = File(ipaPath);
  if (FileSystemEntity.typeSync(ipaPath, followLinks: false) !=
      FileSystemEntityType.file) {
    throw IOSReleasePreparationException(
      "IPA does not exist as a regular file: $ipaPath",
    );
  }
  if (!RegExp(r"^[A-Z0-9]{10}$").hasMatch(expectedTeam)) {
    throw const IOSReleasePreparationException(
      "The expected Apple Team ID is invalid.",
      exitCode: 64,
    );
  }
  if (expectedDeviceCount <= 0 || expectedBuildNumber <= 0) {
    throw const IOSReleasePreparationException(
      "Expected device and build numbers must be positive.",
      exitCode: 64,
    );
  }

  await _requireSuccessfulProcess(
    tools.unzip,
    ["-tq", ipaPath],
    environment: processEnvironment,
    failureMessage: "The IPA ZIP archive failed its integrity check.",
  );
  final entriesResult = await _requireSuccessfulProcess(
    tools.unzip,
    ["-Z1", ipaPath],
    environment: processEnvironment,
    failureMessage: "The IPA ZIP entries could not be listed.",
  );
  final entries = const LineSplitter()
      .convert(entriesResult.stdout as String)
      .where((entry) => entry.isNotEmpty)
      .toList();
  validateSafeZipEntries(entries);
  final appRoots = entries
      .map(
        (entry) =>
            RegExp(r"^(Payload/[^/]+\.app)/Info\.plist$").firstMatch(entry),
      )
      .whereType<RegExpMatch>()
      .map((match) => match.group(1)!)
      .toSet();
  if (appRoots.length != 1) {
    throw IOSReleasePreparationException(
      "Expected one application in the IPA, found ${appRoots.length}.",
    );
  }
  final extensionEntries = entries.where(
    (entry) =>
        entry.contains("/PlugIns/") ||
        entry.contains(".appex/") ||
        entry.endsWith(".appex"),
  );
  if (extensionEntries.isNotEmpty) {
    throw const IOSReleasePreparationException(
      "The core-only self-hosted IPA must not contain app extensions.",
    );
  }

  final extractionDirectory = Directory.systemTemp.createTempSync(
    "ente-ios-ipa-audit-",
  );
  try {
    await _requireSuccessfulProcess(
      tools.unzip,
      ["-qq", ipaPath, "-d", extractionDirectory.path],
      environment: processEnvironment,
      failureMessage: "The IPA could not be extracted for inspection.",
    );
    final links = extractionDirectory
        .listSync(recursive: true, followLinks: false)
        .whereType<Link>()
        .toList();
    if (links.isNotEmpty) {
      throw const IOSReleasePreparationException(
        "The IPA unexpectedly contains symbolic links.",
      );
    }

    final appPath = p.joinAll(<String>[
      extractionDirectory.path,
      ...appRoots.single.split("/"),
    ]);
    final appDirectory = Directory(appPath);
    if (!appDirectory.existsSync()) {
      throw const IOSReleasePreparationException(
        "The IPA application bundle was not extracted.",
      );
    }
    final infoPlistPath = p.join(appPath, "Info.plist");
    final bundleIdentifier = await _plutilRaw(
      tools,
      infoPlistPath,
      "CFBundleIdentifier",
      processEnvironment,
    );
    final marketingVersion = await _plutilRaw(
      tools,
      infoPlistPath,
      "CFBundleShortVersionString",
      processEnvironment,
    );
    final buildNumberValue = await _plutilRaw(
      tools,
      infoPlistPath,
      "CFBundleVersion",
      processEnvironment,
    );
    final executableName = await _plutilRaw(
      tools,
      infoPlistPath,
      "CFBundleExecutable",
      processEnvironment,
    );
    final buildNumber = int.tryParse(buildNumberValue);
    if (bundleIdentifier != expectedBundleIdentifier) {
      throw IOSReleasePreparationException(
        "Expected bundle $expectedBundleIdentifier, found $bundleIdentifier.",
      );
    }
    if (marketingVersion != expectedMarketingVersion ||
        buildNumber != expectedBuildNumber) {
      throw IOSReleasePreparationException(
        "IPA version $marketingVersion+$buildNumberValue does not match "
        "the requested $expectedMarketingVersion+$expectedBuildNumber.",
      );
    }
    final mainExecutable = File(p.join(appPath, executableName));
    if (!mainExecutable.existsSync()) {
      throw const IOSReleasePreparationException(
        "The IPA Info.plist names a missing main executable.",
      );
    }
    final flutterApplication = File(
      p.join(appPath, "Frameworks", "App.framework", "App"),
    );
    if (!flutterApplication.existsSync()) {
      throw const IOSReleasePreparationException(
        "The IPA has no Flutter App.framework application binary.",
      );
    }
    if (!containsBytes(
      flutterApplication.readAsBytesSync(),
      utf8.encode(canonicalEndpoint),
    )) {
      throw IOSReleasePreparationException(
        "The compiled Flutter application does not contain $canonicalEndpoint.",
      );
    }

    final profile = await _auditEmbeddedProfile(
      profilePath: p.join(appPath, "embedded.mobileprovision"),
      temporaryDirectory: extractionDirectory.path,
      expectedTeam: expectedTeam,
      expectedDeviceCount: expectedDeviceCount,
      tools: tools,
      processEnvironment: processEnvironment,
    );
    final signature = await _auditAppSignature(
      appPath: appPath,
      expectedTeam: expectedTeam,
      tools: tools,
      temporaryDirectory: extractionDirectory.path,
      processEnvironment: processEnvironment,
    );
    if (signature.applicationIdentifier != profile.applicationIdentifier ||
        signature.teamIdentifier != profile.teamIdentifier) {
      throw const IOSReleasePreparationException(
        "The signed application identity differs from its provisioning profile.",
      );
    }

    final machOAudit = await _auditMachOFiles(
      appDirectory,
      tools,
      processEnvironment,
    );
    if (!machOAudit.paths.contains(mainExecutable.path) ||
        !machOAudit.paths.contains(flutterApplication.path)) {
      throw const IOSReleasePreparationException(
        "The required application executables were not recognized as Mach-O files.",
      );
    }
    if (!_sameSet(machOAudit.architectures, expectedArchitectures)) {
      throw IOSReleasePreparationException(
        "Expected IPA architectures ${_sorted(expectedArchitectures)}, found "
        "${_sorted(machOAudit.architectures)}.",
      );
    }

    return IOSReleaseAudit(
      bundleIdentifier: bundleIdentifier,
      marketingVersion: marketingVersion,
      buildNumber: buildNumber!,
      compiledDefaultEndpoint: canonicalEndpoint,
      architectures: machOAudit.architectures,
      machOCount: machOAudit.paths.length,
      debuggable: false,
      extensionCount: 0,
      signedEntitlementKeys: signature.entitlements.keys.toSet(),
      applicationIdentifier: signature.applicationIdentifier,
      teamIdentifier: signature.teamIdentifier,
      profileName: profile.name,
      profileUuid: profile.uuid,
      profileExpiration: profile.expiration,
      authorizedDeviceCount: profile.authorizedDeviceCount,
      signingCertificateSha256: profile.certificateSha256,
      certificateNotBefore: profile.certificateNotBefore,
      certificateNotAfter: profile.certificateNotAfter,
      deepSignatureStructureValid: true,
      localTrustChainAccepted: signature.localTrustChainAccepted,
      sha256: await sha256File(
        ipaPath,
        shasum: tools.shasum,
        environment: processEnvironment,
      ),
      sizeBytes: ipa.lengthSync(),
    );
  } finally {
    if (extractionDirectory.existsSync()) {
      extractionDirectory.deleteSync(recursive: true);
    }
  }
}

class _ProfileAudit {
  const _ProfileAudit({
    required this.name,
    required this.uuid,
    required this.expiration,
    required this.authorizedDeviceCount,
    required this.applicationIdentifier,
    required this.teamIdentifier,
    required this.certificateSha256,
    required this.certificateNotBefore,
    required this.certificateNotAfter,
  });

  final String name;
  final String uuid;
  final DateTime expiration;
  final int authorizedDeviceCount;
  final String applicationIdentifier;
  final String teamIdentifier;
  final String certificateSha256;
  final DateTime certificateNotBefore;
  final DateTime certificateNotAfter;
}

class _SignatureAudit {
  const _SignatureAudit({
    required this.applicationIdentifier,
    required this.teamIdentifier,
    required this.entitlements,
    required this.localTrustChainAccepted,
  });

  final String applicationIdentifier;
  final String teamIdentifier;
  final Map<String, Object> entitlements;
  final bool localTrustChainAccepted;
}

class _MachOAudit {
  const _MachOAudit({required this.paths, required this.architectures});

  final Set<String> paths;
  final Set<String> architectures;
}

Future<_ProfileAudit> _auditEmbeddedProfile({
  required String profilePath,
  required String temporaryDirectory,
  required String expectedTeam,
  required int expectedDeviceCount,
  required IOSReleaseToolPaths tools,
  required Map<String, String>? processEnvironment,
}) async {
  if (FileSystemEntity.typeSync(profilePath, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const IOSReleasePreparationException(
      "The IPA has no regular embedded provisioning profile.",
    );
  }
  final decodedProfile = p.join(temporaryDirectory, "profile.plist");
  await _requireSuccessfulProcess(
    tools.security,
    ["cms", "-D", "-i", profilePath, "-o", decodedProfile],
    environment: processEnvironment,
    failureMessage: "The embedded provisioning profile could not be decoded.",
  );
  final teamIdentifier = await _plutilRaw(
    tools,
    decodedProfile,
    "TeamIdentifier.0",
    processEnvironment,
  );
  final profileEntitlements = await _plutilJsonMap(
    tools,
    decodedProfile,
    "Entitlements",
    processEnvironment,
  );
  final applicationIdentifier = profileEntitlements["application-identifier"];
  final entitlementTeam =
      profileEntitlements["com.apple.developer.team-identifier"];
  if (applicationIdentifier is! String || entitlementTeam is! String) {
    throw const IOSReleasePreparationException(
      "The provisioning profile is missing its application or team identity.",
    );
  }
  if (teamIdentifier != expectedTeam || entitlementTeam != expectedTeam) {
    throw const IOSReleasePreparationException(
      "The embedded provisioning profile belongs to another Apple team.",
    );
  }
  if (applicationIdentifier != "$expectedTeam.$expectedBundleIdentifier") {
    throw const IOSReleasePreparationException(
      "The embedded provisioning profile does not match the self-hosted bundle.",
    );
  }
  if (!_sameSet(
    profileEntitlements.keys.toSet(),
    expectedProfileEntitlementKeys,
  )) {
    throw IOSReleasePreparationException(
      "The provisioning profile entitlement set is not the reviewed core-only set: "
      "${_sorted(profileEntitlements.keys.toSet())}.",
    );
  }
  if (profileEntitlements["get-task-allow"] != false) {
    throw const IOSReleasePreparationException(
      "The provisioning profile permits debugging.",
    );
  }
  final keychainGroups = profileEntitlements["keychain-access-groups"];
  if (keychainGroups is! List ||
      !_sameSet(keychainGroups.whereType<String>().toSet(), <String>{
        "$expectedTeam.*",
        "com.apple.token",
      })) {
    throw const IOSReleasePreparationException(
      "The provisioning profile keychain groups are not the reviewed defaults.",
    );
  }
  final provisionsAllDevices = await _plutilOptionalRaw(
    tools,
    decodedProfile,
    "ProvisionsAllDevices",
    processEnvironment,
  );
  if (provisionsAllDevices == "true") {
    throw const IOSReleasePreparationException(
      "The provisioning profile is not device-scoped Ad Hoc provisioning.",
    );
  }
  final devicesValue = await _plutilJson(
    tools,
    decodedProfile,
    "ProvisionedDevices",
    processEnvironment,
  );
  if (devicesValue is! List ||
      devicesValue.length != expectedDeviceCount ||
      devicesValue.any((value) => value is! String || value.isEmpty)) {
    throw const IOSReleasePreparationException(
      "The provisioning profile device count does not match the requested release.",
    );
  }
  final profileName = await _plutilRaw(
    tools,
    decodedProfile,
    "Name",
    processEnvironment,
  );
  final profileUuid = await _plutilRaw(
    tools,
    decodedProfile,
    "UUID",
    processEnvironment,
  );
  if (!RegExp(
    r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$",
  ).hasMatch(profileUuid)) {
    throw const IOSReleasePreparationException(
      "The embedded provisioning profile UUID is invalid.",
    );
  }
  final expirationValue = await _plutilRaw(
    tools,
    decodedProfile,
    "ExpirationDate",
    processEnvironment,
  );
  final expiration = DateTime.tryParse(expirationValue)?.toUtc();
  if (expiration == null || !expiration.isAfter(DateTime.now().toUtc())) {
    throw const IOSReleasePreparationException(
      "The embedded provisioning profile is expired or has an invalid expiry.",
    );
  }

  final certificateXml = await _plutilXml(
    tools,
    decodedProfile,
    "DeveloperCertificates",
    processEnvironment,
  );
  if (RegExp(r"<data>").allMatches(certificateXml).length != 1) {
    throw const IOSReleasePreparationException(
      "The provisioning profile must contain exactly one signing certificate.",
    );
  }
  final certificateBase64 = await _plutilRaw(
    tools,
    decodedProfile,
    "DeveloperCertificates.0",
    processEnvironment,
  );
  List<int> certificateBytes;
  try {
    certificateBytes = base64Decode(
      certificateBase64.replaceAll(RegExp(r"\s"), ""),
    );
  } on FormatException {
    throw const IOSReleasePreparationException(
      "The provisioning profile signing certificate is not valid base64.",
    );
  }
  final certificatePath = p.join(temporaryDirectory, "distribution.cer");
  File(certificatePath).writeAsBytesSync(certificateBytes, flush: true);
  final certificateResult = await _requireSuccessfulProcess(
    tools.openssl,
    [
      "x509",
      "-inform",
      "DER",
      "-in",
      certificatePath,
      "-noout",
      "-fingerprint",
      "-sha256",
      "-startdate",
      "-enddate",
    ],
    environment: processEnvironment,
    failureMessage: "The embedded signing certificate could not be inspected.",
  );
  final certificate = parseOpenSSLCertificateSummary(
    certificateResult.stdout as String,
  );
  final now = DateTime.now().toUtc();
  if (certificate.sha256 != expectedDistributionCertificateSha256) {
    throw const IOSReleasePreparationException(
      "The embedded profile does not contain the pinned distribution certificate.",
    );
  }
  if (certificate.notBefore.isAfter(now) ||
      !certificate.notAfter.isAfter(now)) {
    throw const IOSReleasePreparationException(
      "The embedded distribution certificate is not currently valid.",
    );
  }

  return _ProfileAudit(
    name: profileName,
    uuid: profileUuid,
    expiration: expiration,
    authorizedDeviceCount: devicesValue.length,
    applicationIdentifier: applicationIdentifier,
    teamIdentifier: teamIdentifier,
    certificateSha256: certificate.sha256,
    certificateNotBefore: certificate.notBefore,
    certificateNotAfter: certificate.notAfter,
  );
}

Future<_SignatureAudit> _auditAppSignature({
  required String appPath,
  required String expectedTeam,
  required IOSReleaseToolPaths tools,
  required String temporaryDirectory,
  required Map<String, String>? processEnvironment,
}) async {
  final displayResult = await _requireSuccessfulProcess(
    tools.codesign,
    ["-d", "--verbose=4", appPath],
    environment: processEnvironment,
    failureMessage: "codesign could not display the application signature.",
  );
  final display = "${displayResult.stdout}\n${displayResult.stderr}";
  final identifier = _requiredLineValue(display, "Identifier");
  final teamIdentifier = _requiredLineValue(display, "TeamIdentifier");
  if (identifier != expectedBundleIdentifier ||
      teamIdentifier != expectedTeam) {
    throw const IOSReleasePreparationException(
      "The signed application identity or Apple team is incorrect.",
    );
  }

  final entitlementsPath = p.join(
    temporaryDirectory,
    "signed-entitlements.txt",
  );
  await _requireSuccessfulProcess(
    tools.codesign,
    ["-d", "--entitlements", entitlementsPath, appPath],
    environment: processEnvironment,
    failureMessage: "codesign could not extract the signed entitlements.",
  );
  final entitlementsFile = File(entitlementsPath);
  if (!entitlementsFile.existsSync()) {
    throw const IOSReleasePreparationException(
      "The signed application contains no inspectable entitlements.",
    );
  }
  final entitlements = parseAbstractCodesignEntitlements(
    entitlementsFile.readAsStringSync(),
  );
  validateSignedEntitlements(entitlements, expectedTeam: expectedTeam);

  final verification = await Process.run(
    tools.codesign,
    ["--verify", "--deep", "--strict", "--verbose=2", appPath],
    environment: processEnvironment,
    includeParentEnvironment: processEnvironment == null,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  final localTrustChainAccepted = validateCodesignVerification(verification);
  return _SignatureAudit(
    applicationIdentifier: entitlements["application-identifier"]! as String,
    teamIdentifier:
        entitlements["com.apple.developer.team-identifier"]! as String,
    entitlements: entitlements,
    localTrustChainAccepted: localTrustChainAccepted,
  );
}

Future<_MachOAudit> _auditMachOFiles(
  Directory appDirectory,
  IOSReleaseToolPaths tools,
  Map<String, String>? processEnvironment,
) async {
  final paths = <String>{};
  final architectures = <String>{};
  for (final entity in appDirectory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) {
      continue;
    }
    final typeResult = await _requireSuccessfulProcess(
      tools.file,
      ["-b", "--mime-type", entity.path],
      environment: processEnvironment,
      failureMessage: "Could not identify an IPA file type.",
    );
    if (!(typeResult.stdout as String).contains("application/x-mach-binary")) {
      continue;
    }
    final lipoResult = await _requireSuccessfulProcess(
      tools.lipo,
      ["-archs", entity.path],
      environment: processEnvironment,
      failureMessage: "Could not inspect a Mach-O architecture.",
    );
    final fileArchitectures = (lipoResult.stdout as String)
        .trim()
        .split(RegExp(r"\s+"))
        .where((value) => value.isNotEmpty)
        .toSet();
    if (fileArchitectures.isEmpty ||
        !_sameSet(fileArchitectures, expectedArchitectures)) {
      throw IOSReleasePreparationException(
        "Mach-O file ${p.basename(entity.path)} has unexpected architectures "
        "${_sorted(fileArchitectures)}.",
      );
    }
    paths.add(entity.path);
    architectures.addAll(fileArchitectures);
  }
  if (paths.isEmpty) {
    throw const IOSReleasePreparationException(
      "The IPA contains no Mach-O executables.",
    );
  }
  return _MachOAudit(paths: paths, architectures: architectures);
}

class OpenSSLCertificateSummary {
  const OpenSSLCertificateSummary({
    required this.sha256,
    required this.notBefore,
    required this.notAfter,
  });

  final String sha256;
  final DateTime notBefore;
  final DateTime notAfter;
}

OpenSSLCertificateSummary parseOpenSSLCertificateSummary(String output) {
  final fingerprint = RegExp(
    r"^sha256 Fingerprint=([0-9A-Fa-f:]+)$",
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(output);
  final notBefore = RegExp(
    r"^notBefore=(.+)$",
    multiLine: true,
  ).firstMatch(output);
  final notAfter = RegExp(
    r"^notAfter=(.+)$",
    multiLine: true,
  ).firstMatch(output);
  if (fingerprint == null || notBefore == null || notAfter == null) {
    throw const IOSReleasePreparationException(
      "OpenSSL output is missing certificate fingerprint or validity dates.",
    );
  }
  final sha256 = fingerprint.group(1)!.replaceAll(":", "").toLowerCase();
  if (!RegExp(r"^[0-9a-f]{64}$").hasMatch(sha256)) {
    throw const IOSReleasePreparationException(
      "OpenSSL returned an invalid certificate SHA-256 fingerprint.",
    );
  }
  return OpenSSLCertificateSummary(
    sha256: sha256,
    notBefore: parseOpenSSLDate(notBefore.group(1)!),
    notAfter: parseOpenSSLDate(notAfter.group(1)!),
  );
}

DateTime parseOpenSSLDate(String value) {
  final match = RegExp(
    r"^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+"
    r"([0-9]{1,2})\s+([0-9]{2}):([0-9]{2}):([0-9]{2})\s+"
    r"([0-9]{4})\s+GMT$",
  ).firstMatch(value.trim());
  if (match == null) {
    throw IOSReleasePreparationException(
      "OpenSSL returned an unsupported certificate date '$value'.",
    );
  }
  const months = <String, int>{
    "Jan": 1,
    "Feb": 2,
    "Mar": 3,
    "Apr": 4,
    "May": 5,
    "Jun": 6,
    "Jul": 7,
    "Aug": 8,
    "Sep": 9,
    "Oct": 10,
    "Nov": 11,
    "Dec": 12,
  };
  return DateTime.utc(
    int.parse(match.group(6)!),
    months[match.group(1)!]!,
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
  );
}

Map<String, Object> parseAbstractCodesignEntitlements(String output) {
  final result = <String, Object>{};
  String? pendingKey;
  for (final rawLine in const LineSplitter().convert(output)) {
    final line = rawLine.trim();
    final keyMatch = RegExp(r"^\[Key\]\s+(.+)$").firstMatch(line);
    if (keyMatch != null) {
      pendingKey = keyMatch.group(1)!;
      continue;
    }
    if (pendingKey == null) {
      continue;
    }
    final stringMatch = RegExp(r"^\[String\]\s+(.+)$").firstMatch(line);
    if (stringMatch != null) {
      result[pendingKey] = stringMatch.group(1)!;
      pendingKey = null;
      continue;
    }
    final boolMatch = RegExp(r"^\[Bool\]\s+(true|false)$").firstMatch(line);
    if (boolMatch != null) {
      result[pendingKey] = boolMatch.group(1) == "true";
      pendingKey = null;
    }
  }
  if (pendingKey != null || result.isEmpty) {
    throw const IOSReleasePreparationException(
      "codesign returned incomplete abstract entitlements.",
    );
  }
  return result;
}

void validateSignedEntitlements(
  Map<String, Object> entitlements, {
  required String expectedTeam,
}) {
  if (!_sameSet(entitlements.keys.toSet(), expectedSignedEntitlementKeys)) {
    throw IOSReleasePreparationException(
      "The signed entitlement set is not core-only: "
      "${_sorted(entitlements.keys.toSet())}.",
    );
  }
  if (entitlements["application-identifier"] !=
          "$expectedTeam.$expectedBundleIdentifier" ||
      entitlements["com.apple.developer.team-identifier"] != expectedTeam ||
      entitlements["get-task-allow"] != false) {
    throw const IOSReleasePreparationException(
      "The signed identity, Apple team, or debug entitlement is incorrect.",
    );
  }
}

bool validateCodesignVerification(ProcessResult result) {
  if (result.exitCode == 0) {
    return true;
  }
  final details = "${result.stdout}\n${result.stderr}".trim();
  final lines = const LineSplitter()
      .convert(details)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final onlyLocalTrustFailure =
      lines.isNotEmpty &&
      lines.any((line) => line.contains("CSSMERR_TP_NOT_TRUSTED")) &&
      lines.every(
        (line) =>
            line.contains("CSSMERR_TP_NOT_TRUSTED") ||
            line.startsWith("In architecture:"),
      );
  if (onlyLocalTrustFailure) {
    return false;
  }
  throw IOSReleasePreparationException(
    details.isEmpty
        ? "codesign rejected the application signature."
        : "codesign rejected the application signature.\n$details",
  );
}

void validateSafeZipEntries(List<String> entries) {
  if (entries.isEmpty) {
    throw const IOSReleasePreparationException("The IPA ZIP is empty.");
  }
  for (final entry in entries) {
    final segments = entry.split("/");
    if (entry.startsWith("/") ||
        entry.contains("\\") ||
        segments.contains("..") ||
        segments.contains(".")) {
      throw IOSReleasePreparationException(
        "The IPA contains an unsafe ZIP entry '$entry'.",
      );
    }
  }
}

String _requiredLineValue(String output, String key) {
  final match = RegExp(
    "^${RegExp.escape(key)}=(.+)\$",
    multiLine: true,
  ).firstMatch(output);
  if (match == null || match.group(1)!.trim().isEmpty) {
    throw IOSReleasePreparationException("codesign output is missing $key.");
  }
  return match.group(1)!.trim();
}

Future<String> _plutilRaw(
  IOSReleaseToolPaths tools,
  String plistPath,
  String keyPath,
  Map<String, String>? environment,
) async {
  final result = await _requireSuccessfulProcess(
    tools.plutil,
    ["-extract", keyPath, "raw", "-o", "-", plistPath],
    environment: environment,
    failureMessage: "Required plist value '$keyPath' is missing.",
  );
  final value = (result.stdout as String).trim();
  if (value.isEmpty) {
    throw IOSReleasePreparationException(
      "Required plist value '$keyPath' is empty.",
    );
  }
  return value;
}

Future<String?> _plutilOptionalRaw(
  IOSReleaseToolPaths tools,
  String plistPath,
  String keyPath,
  Map<String, String>? environment,
) async {
  final result = await Process.run(
    tools.plutil,
    ["-extract", keyPath, "raw", "-o", "-", plistPath],
    environment: environment,
    includeParentEnvironment: environment == null,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    return null;
  }
  final value = (result.stdout as String).trim();
  return value.isEmpty ? null : value;
}

Future<Object?> _plutilJson(
  IOSReleaseToolPaths tools,
  String plistPath,
  String keyPath,
  Map<String, String>? environment,
) async {
  final result = await _requireSuccessfulProcess(
    tools.plutil,
    ["-extract", keyPath, "json", "-o", "-", plistPath],
    environment: environment,
    failureMessage: "Required plist object '$keyPath' is missing.",
  );
  try {
    return jsonDecode(result.stdout as String);
  } on FormatException {
    throw IOSReleasePreparationException(
      "Plist object '$keyPath' is not valid JSON.",
    );
  }
}

Future<Map<String, Object?>> _plutilJsonMap(
  IOSReleaseToolPaths tools,
  String plistPath,
  String keyPath,
  Map<String, String>? environment,
) async {
  final value = await _plutilJson(tools, plistPath, keyPath, environment);
  if (value is! Map) {
    throw IOSReleasePreparationException(
      "Plist object '$keyPath' is not a dictionary.",
    );
  }
  return value.cast<String, Object?>();
}

Future<String> _plutilXml(
  IOSReleaseToolPaths tools,
  String plistPath,
  String keyPath,
  Map<String, String>? environment,
) async {
  final result = await _requireSuccessfulProcess(
    tools.plutil,
    ["-extract", keyPath, "xml1", "-o", "-", plistPath],
    environment: environment,
    failureMessage: "Required plist object '$keyPath' is missing.",
  );
  return result.stdout as String;
}

Future<XcodeVersion> readXcodeVersion(
  String xcodebuild, {
  Map<String, String>? environment,
}) async {
  final result = await _requireSuccessfulProcess(
    xcodebuild,
    const ["-version"],
    environment: environment,
    failureMessage: "Could not read the active Xcode version.",
  );
  final output = result.stdout as String;
  final version = RegExp(r"^Xcode\s+(.+)$", multiLine: true).firstMatch(output);
  final buildVersion = RegExp(
    r"^Build version\s+(.+)$",
    multiLine: true,
  ).firstMatch(output);
  if (version == null || buildVersion == null) {
    throw const IOSReleasePreparationException(
      "xcodebuild returned an unexpected version format.",
      exitCode: 69,
    );
  }
  return XcodeVersion(
    version: version.group(1)!.trim(),
    buildVersion: buildVersion.group(1)!.trim(),
  );
}

String parsePubspecMarketingVersion(String pubspec) {
  final match = RegExp(
    r"^version:\s*([^\s+]+)\+[0-9]+\s*$",
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw const IOSReleasePreparationException(
      "pubspec.yaml must contain version: <name>+<positive code>.",
      exitCode: 65,
    );
  }
  return match.group(1)!;
}

String canonicalizeConfigurableEndpoint(String endpoint) {
  try {
    return EndpointPolicy(
      mode: EndpointMode.configurable,
      compiledEndpoint: endpoint,
    ).configurableDefaultEndpoint;
  } on EndpointPolicyException catch (error) {
    throw IOSReleasePreparationException(
      "Invalid ENTE_SELF_HOSTED_ENDPOINT: ${error.message}",
      exitCode: 64,
    );
  }
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
    throw IOSReleasePreparationException(
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
    throw IOSReleasePreparationException(
      "origin must identify one GitHub owner and repository, found '$remote'.",
      exitCode: 65,
    );
  }
  return "https://github.com$path";
}

Map<String, String> sanitizedIOSPreparationEnvironment(
  Map<String, String> environment,
) {
  final result = Map<String, String>.from(environment);
  result.removeWhere(
    (key, _) =>
        key == "FIREBASE_TOKEN" ||
        key == "FIREBASE_CLI" ||
        key.startsWith("ENTE_FIREBASE_") ||
        key.startsWith("GOOGLE_") ||
        key.startsWith("GCLOUD_"),
  );
  return result;
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
    failureMessage: "Could not calculate the IPA SHA-256.",
  );
  final match = RegExp(
    r"^([0-9a-fA-F]{64})\s",
  ).firstMatch((result.stdout as String).trim());
  if (match == null) {
    throw const IOSReleasePreparationException(
      "shasum returned an unexpected SHA-256 format.",
    );
  }
  return match.group(1)!.toLowerCase();
}

String _requiredEnvironment(Map<String, String> environment, String name) {
  final value = environment[name];
  if (value == null || value.trim().isEmpty) {
    throw IOSReleasePreparationException(
      "$name is required for iOS release preparation.",
      exitCode: 64,
    );
  }
  return value;
}

String _resolvePrivateProfile(String path, String repositoryRoot) {
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const IOSReleasePreparationException(
      "ENTE_IOS_ADHOC_PROFILE must name a regular, non-symbolic-link file.",
      exitCode: 64,
    );
  }
  final resolved = File(path).resolveSymbolicLinksSync();
  if (p.equals(resolved, repositoryRoot) ||
      p.isWithin(repositoryRoot, resolved)) {
    throw const IOSReleasePreparationException(
      "The Ad Hoc profile must remain outside the Git repository.",
      exitCode: 64,
    );
  }
  return resolved;
}

String _resolveExternalOutputDirectory(String path, String repositoryRoot) {
  if (FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.file) {
    throw const IOSReleasePreparationException(
      "The iOS release output path is a file, not a directory.",
      exitCode: 64,
    );
  }
  final directory = Directory(path)..createSync(recursive: true);
  final resolved = directory.resolveSymbolicLinksSync();
  if (p.equals(resolved, repositoryRoot) ||
      p.isWithin(repositoryRoot, resolved)) {
    throw const IOSReleasePreparationException(
      "The iOS release output directory must be outside the Git repository.",
      exitCode: 64,
    );
  }
  final permissionResult = Process.runSync("chmod", ["0700", resolved]);
  if (permissionResult.exitCode != 0 ||
      (Directory(resolved).statSync().mode & 0x1ff) != 0x1c0) {
    throw const IOSReleasePreparationException(
      "The iOS release output directory could not be restricted to mode 0700.",
      exitCode: 73,
    );
  }
  return resolved;
}

Future<void> _requireTrackedPathMatchesCommit(
  String repositoryRoot,
  String commit,
  String relativePath,
) async {
  final tracked = await _gitOutput(
    ["ls-tree", "-r", "--name-only", commit, "--", relativePath],
    workingDirectory: repositoryRoot,
    allowEmpty: true,
  );
  if (!const LineSplitter().convert(tracked).contains(relativePath)) {
    throw IOSReleasePreparationException(
      "$relativePath is not present in the pushed source commit.",
      exitCode: 65,
    );
  }
  final result = await Process.run(
    "git",
    ["diff", "--quiet", commit, "--", relativePath],
    workingDirectory: repositoryRoot,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw IOSReleasePreparationException(
      "$relativePath differs from the pushed source commit. Commit and push "
      "the release tooling before preparing.",
      exitCode: 65,
    );
  }
}

Future<void> _requireCleanCheckout(
  String checkoutDirectory, {
  required String expectedCommit,
}) async {
  final commit = await _gitOutput([
    "rev-parse",
    "HEAD",
  ], workingDirectory: checkoutDirectory);
  if (commit != expectedCommit) {
    throw const IOSReleasePreparationException(
      "The detached release checkout changed commits during preparation.",
      exitCode: 65,
    );
  }
  final status = await _gitOutput(
    ["status", "--porcelain", "--untracked-files=normal"],
    workingDirectory: checkoutDirectory,
    allowEmpty: true,
  );
  if (status.isNotEmpty) {
    throw IOSReleasePreparationException(
      "The detached release checkout is not clean:\n$status",
      exitCode: 65,
    );
  }
}

Future<void> _cleanupDetachedWorktree({
  required String repositoryRoot,
  required String checkoutDirectory,
  required Directory workRoot,
  required bool worktreeAdded,
}) async {
  if (worktreeAdded) {
    final removal = await Process.run(
      "git",
      ["worktree", "remove", "--force", checkoutDirectory],
      workingDirectory: repositoryRoot,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (removal.exitCode != 0) {
      stderr.writeln(
        "Warning: could not remove temporary Git worktree $checkoutDirectory.",
      );
    }
    await Process.run(
      "git",
      const ["worktree", "prune"],
      workingDirectory: repositoryRoot,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }
  if (workRoot.existsSync()) {
    try {
      workRoot.deleteSync(recursive: true);
    } on FileSystemException {
      stderr.writeln(
        "Warning: could not remove temporary release directory ${workRoot.path}.",
      );
    }
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
    throw IOSReleasePreparationException(
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
      includeParentEnvironment: environment == null,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException catch (error) {
    throw IOSReleasePreparationException(
      "$failureMessage ${error.message}",
      exitCode: 69,
    );
  }
  if (result.exitCode != 0) {
    final details = (result.stderr as String).trim();
    throw IOSReleasePreparationException(
      details.isEmpty ? failureMessage : "$failureMessage\n$details",
    );
  }
  return result;
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
  throw IOSReleasePreparationException(
    "Required command '$name' was not found on PATH.",
    exitCode: 69,
  );
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

String _sorted(Set<String> values) {
  final sorted = values.toList()..sort();
  return sorted.join(", ");
}
