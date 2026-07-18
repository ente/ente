import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;

import "prepare_self_hosted_ios_release.dart" as preparation;

const publicationToolName = "ente-self-hosted-ios-firebase-publisher";
const publicationToolVersion = "1.0.0";
const publicationReceiptSchemaVersion = 1;
const trustedIOSTesterGroupAlias = "trusted-ios-testers";
const _maximumReleaseNotesBytes = 10000;

const _usage =
    """
Publish one prepared Ente Photos iOS release to Firebase App Distribution.

Usage:
  ./scripts/publish_self_hosted_ios_release.sh \\
    --manifest /absolute/path/release.manifest.json \\
    --receipt-dir /absolute/path/firebase-receipts \\
    --firebase-project your-project-id \\
    --firebase-app 1:1234567890:ios:opaque-id

Options:
  --release-notes-file PATH  Append operator notes to generated audit notes.
  --preflight-only           Verify everything without prompting or uploading.
  -h, --help                 Show this help.

Environment alternatives:
  ENTE_IOS_RELEASE_MANIFEST
  ENTE_FIREBASE_RELEASE_RECEIPT_DIR
  ENTE_FIREBASE_PROJECT_ID
  ENTE_FIREBASE_IOS_APP_ID
  FIREBASE_CLI                       Firebase executable; otherwise use PATH.

The Firebase group is pinned to '$trustedIOSTesterGroupAlias'. Publishing
requires typing the exact release-specific confirmation shown after all checks.
The command never invokes Flutter, Xcode, signing, or Apple account mutation.
""";

Future<void> main(List<String> arguments) async {
  try {
    final options = IOSPublicationOptions.parse(
      arguments,
      environment: Platform.environment,
    );
    if (options.showHelp) {
      stdout.write(_usage);
      return;
    }

    final result = await publishSelfHostedIOSRelease(options);
    if (result == null) {
      return;
    }
    stdout.writeln();
    stdout.writeln("Firebase iOS publication completed:");
    stdout.writeln("  Receipt: ${result.receiptPath}");
    stdout.writeln("  Console: ${result.references.firebaseConsoleUri}");
    stdout.writeln("  Tester: ${result.references.testingUri}");
    stdout.writeln(
      "  Binary: ${result.references.binaryDownloadUri} (expires in 1 hour)",
    );
  } on IOSPublicationException catch (error) {
    stderr.writeln("Firebase iOS publication failed: ${error.message}");
    exitCode = error.exitCode;
  } on Object catch (error) {
    stderr.writeln("Firebase iOS publication failed unexpectedly: $error");
    exitCode = 70;
  }
}

class IOSPublicationOptions {
  const IOSPublicationOptions({
    required this.manifestPath,
    required this.receiptDirectory,
    required this.firebaseProjectId,
    required this.firebaseAppId,
    required this.environment,
    this.releaseNotesFile,
    this.preflightOnly = false,
    this.showHelp = false,
  });

  factory IOSPublicationOptions.parse(
    List<String> arguments, {
    required Map<String, String> environment,
  }) {
    if (arguments.length == 1 &&
        (arguments.single == "--help" || arguments.single == "-h")) {
      return IOSPublicationOptions(
        manifestPath: "",
        receiptDirectory: "",
        firebaseProjectId: "",
        firebaseAppId: "",
        environment: environment,
        showHelp: true,
      );
    }

    String? manifestPath;
    String? receiptDirectory;
    String? firebaseProjectId;
    String? firebaseAppId;
    String? releaseNotesFile;
    var preflightOnly = false;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      String readValue(String name) {
        if (index + 1 >= arguments.length) {
          throw IOSPublicationException(
            "$name requires a value.",
            exitCode: 64,
          );
        }
        return arguments[++index];
      }

      if (argument == "--manifest") {
        manifestPath = readValue(argument);
      } else if (argument.startsWith("--manifest=")) {
        manifestPath = argument.substring("--manifest=".length);
      } else if (argument == "--receipt-dir") {
        receiptDirectory = readValue(argument);
      } else if (argument.startsWith("--receipt-dir=")) {
        receiptDirectory = argument.substring("--receipt-dir=".length);
      } else if (argument == "--firebase-project") {
        firebaseProjectId = readValue(argument);
      } else if (argument.startsWith("--firebase-project=")) {
        firebaseProjectId = argument.substring("--firebase-project=".length);
      } else if (argument == "--firebase-app") {
        firebaseAppId = readValue(argument);
      } else if (argument.startsWith("--firebase-app=")) {
        firebaseAppId = argument.substring("--firebase-app=".length);
      } else if (argument == "--release-notes-file") {
        releaseNotesFile = readValue(argument);
      } else if (argument.startsWith("--release-notes-file=")) {
        releaseNotesFile = argument.substring("--release-notes-file=".length);
      } else if (argument == "--preflight-only") {
        preflightOnly = true;
      } else {
        throw IOSPublicationException(
          "Unknown argument '$argument'.\n\n$_usage",
          exitCode: 64,
        );
      }
    }

    manifestPath ??= environment["ENTE_IOS_RELEASE_MANIFEST"];
    receiptDirectory ??= environment["ENTE_FIREBASE_RELEASE_RECEIPT_DIR"];
    firebaseProjectId ??= environment["ENTE_FIREBASE_PROJECT_ID"];
    firebaseAppId ??= environment["ENTE_FIREBASE_IOS_APP_ID"];

    final requiredValues = <String, String?>{
      "--manifest or ENTE_IOS_RELEASE_MANIFEST": manifestPath,
      "--receipt-dir or ENTE_FIREBASE_RELEASE_RECEIPT_DIR": receiptDirectory,
      "--firebase-project or ENTE_FIREBASE_PROJECT_ID": firebaseProjectId,
      "--firebase-app or ENTE_FIREBASE_IOS_APP_ID": firebaseAppId,
    };
    for (final entry in requiredValues.entries) {
      if (entry.value == null || entry.value!.trim().isEmpty) {
        throw IOSPublicationException("Provide ${entry.key}.", exitCode: 64);
      }
    }

    manifestPath = p.normalize(manifestPath!);
    receiptDirectory = p.normalize(receiptDirectory!);
    if (!p.isAbsolute(manifestPath)) {
      throw const IOSPublicationException(
        "The prepared manifest path must be absolute.",
        exitCode: 64,
      );
    }
    if (!p.isAbsolute(receiptDirectory)) {
      throw const IOSPublicationException(
        "The Firebase receipt directory must be absolute.",
        exitCode: 64,
      );
    }
    if (releaseNotesFile != null) {
      releaseNotesFile = p.normalize(releaseNotesFile);
      if (!p.isAbsolute(releaseNotesFile)) {
        throw const IOSPublicationException(
          "The release-notes file path must be absolute.",
          exitCode: 64,
        );
      }
    }
    firebaseProjectId = firebaseProjectId!.trim();
    firebaseAppId = firebaseAppId!.trim();
    if (firebaseProjectId.startsWith("-") || firebaseAppId.startsWith("-")) {
      throw const IOSPublicationException(
        "Firebase identifiers cannot start with '-'.",
        exitCode: 64,
      );
    }

    return IOSPublicationOptions(
      manifestPath: manifestPath,
      receiptDirectory: receiptDirectory,
      firebaseProjectId: firebaseProjectId,
      firebaseAppId: firebaseAppId,
      releaseNotesFile: releaseNotesFile,
      preflightOnly: preflightOnly,
      environment: Map<String, String>.unmodifiable(environment),
    );
  }

  final String manifestPath;
  final String receiptDirectory;
  final String firebaseProjectId;
  final String firebaseAppId;
  final String? releaseNotesFile;
  final bool preflightOnly;
  final bool showHelp;
  final Map<String, String> environment;
}

class IOSPublicationException implements Exception {
  const IOSPublicationException(this.message, {this.exitCode = 66});

  final String message;
  final int exitCode;

  @override
  String toString() => message;
}

class PreparedIOSReleaseManifest {
  const PreparedIOSReleaseManifest({
    required this.manifestPath,
    required this.manifestSha256,
    required this.releaseId,
    required this.ipaPath,
    required this.ipaSha256,
    required this.ipaSizeBytes,
    required this.commit,
    required this.sourceRemote,
    required this.sourceCommitUrl,
    required this.bundleIdentifier,
    required this.marketingVersion,
    required this.buildNumber,
    required this.compiledDefaultEndpoint,
    required this.architectures,
    required this.machOCount,
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
    required this.xcodeVersion,
    required this.xcodeBuildVersion,
  });

  final String manifestPath;
  final String manifestSha256;
  final String releaseId;
  final String ipaPath;
  final String ipaSha256;
  final int ipaSizeBytes;
  final String commit;
  final String sourceRemote;
  final String sourceCommitUrl;
  final String bundleIdentifier;
  final String marketingVersion;
  final int buildNumber;
  final String compiledDefaultEndpoint;
  final Set<String> architectures;
  final int machOCount;
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
  final String xcodeVersion;
  final String xcodeBuildVersion;
}

class FirebaseIOSRegistration {
  const FirebaseIOSRegistration({
    required this.projectId,
    required this.appId,
    required this.bundleIdentifier,
    required this.groupName,
    required this.groupDisplayName,
  });

  final String projectId;
  final String appId;
  final String bundleIdentifier;
  final String groupName;
  final String groupDisplayName;
}

class FirebaseIOSReleaseReferences {
  const FirebaseIOSReleaseReferences({
    required this.firebaseConsoleUri,
    required this.testingUri,
    required this.binaryDownloadUri,
    required this.uploadDisposition,
  });

  final String firebaseConsoleUri;
  final String testingUri;
  final String binaryDownloadUri;
  final String uploadDisposition;
}

class IOSPublicationResult {
  const IOSPublicationResult({
    required this.receiptPath,
    required this.references,
  });

  final String receiptPath;
  final FirebaseIOSReleaseReferences references;
}

typedef IOSPublicationProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

typedef IOSPreparedReleaseAuditor =
    Future<void> Function(
      PreparedIOSReleaseManifest prepared, {
      required Map<String, String> environment,
    });

Future<ProcessResult> runIOSPublicationProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
  includeParentEnvironment: false,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

class FirebaseIOSCliClient {
  FirebaseIOSCliClient({
    required this.executable,
    required this.projectId,
    required this.workingDirectory,
    required Map<String, String> environment,
    this.runner = runIOSPublicationProcess,
  }) : environment = sanitizedIOSPublicationEnvironment(environment);

  final String executable;
  final String projectId;
  final String workingDirectory;
  final Map<String, String> environment;
  final IOSPublicationProcessRunner runner;

  Future<FirebaseIOSRegistration> verifyRegistration({
    required String appId,
    required String expectedBundleIdentifier,
  }) async {
    final appsResult = await _runJson([
      "apps:list",
      "IOS",
      "--project",
      projectId,
      "--json",
      "--non-interactive",
    ], "Could not list Firebase iOS apps.");
    final app = validateFirebaseIOSApp(
      appsResult,
      projectId: projectId,
      appId: appId,
      expectedBundleIdentifier: expectedBundleIdentifier,
    );

    final groupsResult = await _runJson([
      "appdistribution:groups:list",
      "--project",
      projectId,
      "--json",
      "--non-interactive",
    ], "Could not list Firebase App Distribution groups.");
    final group = validateFirebaseIOSGroup(
      groupsResult,
      expectedAlias: trustedIOSTesterGroupAlias,
    );

    return FirebaseIOSRegistration(
      projectId: app["projectId"]! as String,
      appId: app["appId"]! as String,
      bundleIdentifier: app["bundleId"]! as String,
      groupName: group["name"]! as String,
      groupDisplayName: group["displayName"]! as String,
    );
  }

  Future<ProcessResult> distribute({
    required String ipaPath,
    required String appId,
    required String releaseNotesFile,
  }) => runner(
    executable,
    [
      "appdistribution:distribute",
      ipaPath,
      "--app",
      appId,
      "--groups",
      trustedIOSTesterGroupAlias,
      "--release-notes-file",
      releaseNotesFile,
      "--project",
      projectId,
      "--json",
      "--non-interactive",
    ],
    workingDirectory: workingDirectory,
    environment: environment,
  );

  Future<Map<String, dynamic>> _runJson(
    List<String> arguments,
    String failureMessage,
  ) async {
    ProcessResult result;
    try {
      result = await runner(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    } on ProcessException catch (error) {
      throw IOSPublicationException(
        "$failureMessage ${error.message}",
        exitCode: 69,
      );
    }
    if (result.exitCode != 0) {
      throw IOSPublicationException(
        _firebaseFailureDetails(result, fallback: failureMessage),
        exitCode: 69,
      );
    }
    return decodeFirebaseIOSCliSuccess(result.stdout as String);
  }
}

Future<IOSPublicationResult?> publishSelfHostedIOSRelease(
  IOSPublicationOptions options, {
  IOSPublicationProcessRunner processRunner = runIOSPublicationProcess,
  IOSPreparedReleaseAuditor releaseAuditor = reAuditPreparedIOSIpa,
  String? Function()? readConfirmation,
  String? appDirectoryOverride,
}) async {
  final appDirectory = appDirectoryOverride == null
      ? p.dirname(p.dirname(Platform.script.toFilePath()))
      : p.normalize(appDirectoryOverride);
  final repositoryRoot = Directory(
    p.dirname(p.dirname(p.dirname(appDirectory))),
  ).resolveSymbolicLinksSync();
  final receiptDirectory = prepareExternalIOSReceiptDirectory(
    options.receiptDirectory,
    repositoryRoot: repositoryRoot,
  );
  final firebaseWorkingDirectory = receiptDirectory.createTempSync(
    ".firebase-ios-publication-",
  );

  try {
    final firebaseExecutable = resolveFirebaseIOSExecutable(
      options.environment,
    );
    final firebase = FirebaseIOSCliClient(
      executable: firebaseExecutable,
      projectId: options.firebaseProjectId,
      workingDirectory: firebaseWorkingDirectory.path,
      environment: options.environment,
      runner: processRunner,
    );
    var prepared = await loadAndValidatePreparedIOSManifest(
      options.manifestPath,
      repositoryRoot: repositoryRoot,
      environment: options.environment,
    );
    await releaseAuditor(prepared, environment: options.environment);
    validateIOSPublicationVersionLedger(
      receiptDirectory.path,
      firebaseAppId: options.firebaseAppId,
      bundleIdentifier: prepared.bundleIdentifier,
      buildNumber: prepared.buildNumber,
    );
    final releaseNotes = buildFirebaseIOSReleaseNotes(
      prepared,
      operatorNotes: readOptionalIOSReleaseNotes(options.releaseNotesFile),
    );
    var registration = await firebase.verifyRegistration(
      appId: options.firebaseAppId,
      expectedBundleIdentifier: prepared.bundleIdentifier,
    );

    printIOSPublicationSummary(
      prepared,
      registration,
      receiptDirectory: receiptDirectory.path,
      preflightOnly: options.preflightOnly,
    );
    if (options.preflightOnly) {
      stdout.writeln();
      stdout.writeln("Preflight passed. No Firebase upload was performed.");
      return null;
    }

    final expectedConfirmation = confirmationForIOSRelease(prepared.releaseId);
    stdout.writeln();
    stdout.writeln(
      "This will upload the audited IPA and notify "
      "'$trustedIOSTesterGroupAlias'.",
    );
    stdout.write("Type '$expectedConfirmation' to continue: ");
    final actualConfirmation = readConfirmation?.call() ?? stdin.readLineSync();
    requireExactIOSConfirmation(actualConfirmation, expectedConfirmation);

    // Close the confirmation race immediately before the only mutating call.
    final confirmedPrepared = await loadAndValidatePreparedIOSManifest(
      options.manifestPath,
      repositoryRoot: repositoryRoot,
      environment: options.environment,
    );
    await releaseAuditor(confirmedPrepared, environment: options.environment);
    requireSamePreparedIOSRelease(prepared, confirmedPrepared);
    prepared = confirmedPrepared;
    validateIOSPublicationVersionLedger(
      receiptDirectory.path,
      firebaseAppId: options.firebaseAppId,
      bundleIdentifier: prepared.bundleIdentifier,
      buildNumber: prepared.buildNumber,
    );
    registration = await firebase.verifyRegistration(
      appId: options.firebaseAppId,
      expectedBundleIdentifier: prepared.bundleIdentifier,
    );

    final finalReceiptPath = p.join(
      receiptDirectory.path,
      "${prepared.releaseId}.firebase-ios-release.json",
    );
    if (File(finalReceiptPath).existsSync()) {
      throw IOSPublicationException(
        "A Firebase receipt already exists for this release: $finalReceiptPath",
        exitCode: 73,
      );
    }
    final notesFile = File(
      p.join(firebaseWorkingDirectory.path, "release-notes.txt"),
    )..writeAsStringSync(releaseNotes, flush: true);
    final notesPermissions = Process.runSync("chmod", ["0600", notesFile.path]);
    if (notesPermissions.exitCode != 0) {
      throw const IOSPublicationException(
        "Could not protect the temporary Firebase release notes.",
        exitCode: 73,
      );
    }

    stdout.writeln();
    stdout.writeln("Uploading the unchanged audited IPA to Firebase...");
    ProcessResult upload;
    try {
      upload = await firebase.distribute(
        ipaPath: prepared.ipaPath,
        appId: options.firebaseAppId,
        releaseNotesFile: notesFile.path,
      );
    } on ProcessException catch (error) {
      final attemptPath = writeFailedIOSPublicationAttempt(
        receiptDirectory.path,
        prepared: prepared,
        registration: registration,
        releaseNotes: releaseNotes,
        firebaseExitCode: 69,
        firebaseOutput: error.message,
      );
      throw IOSPublicationException(
        "Firebase could not be started. The attempt record is $attemptPath",
        exitCode: 69,
      );
    }

    final firebaseOutput = [
      upload.stdout as String,
      upload.stderr as String,
    ].where((value) => value.trim().isNotEmpty).join("\n");
    if (upload.exitCode != 0) {
      final attemptPath = writeFailedIOSPublicationAttempt(
        receiptDirectory.path,
        prepared: prepared,
        registration: registration,
        releaseNotes: releaseNotes,
        firebaseExitCode: upload.exitCode,
        firebaseOutput: firebaseOutput,
      );
      throw IOSPublicationException(
        "${_firebaseFailureDetails(upload, fallback: "Firebase rejected the publication.")}\n"
        "An upload may have occurred before the failure. Inspect Firebase "
        "before retrying. Attempt record: $attemptPath",
        exitCode: 69,
      );
    }

    FirebaseIOSReleaseReferences references;
    try {
      references = parseFirebaseIOSReleaseReferences(firebaseOutput);
    } on IOSPublicationException catch (error) {
      final attemptPath = writeFailedIOSPublicationAttempt(
        receiptDirectory.path,
        prepared: prepared,
        registration: registration,
        releaseNotes: releaseNotes,
        firebaseExitCode: upload.exitCode,
        firebaseOutput: firebaseOutput,
      );
      throw IOSPublicationException(
        "${error.message} Firebase reported success, so do not retry before "
        "checking the console. Attempt record: $attemptPath",
        exitCode: 69,
      );
    }

    final receipt = buildSuccessfulIOSPublicationReceipt(
      prepared: prepared,
      registration: registration,
      releaseNotes: releaseNotes,
      references: references,
    );
    writeImmutableIOSJson(finalReceiptPath, receipt);
    return IOSPublicationResult(
      receiptPath: finalReceiptPath,
      references: references,
    );
  } finally {
    if (firebaseWorkingDirectory.existsSync()) {
      firebaseWorkingDirectory.deleteSync(recursive: true);
    }
  }
}

Directory prepareExternalIOSReceiptDirectory(
  String path, {
  required String repositoryRoot,
}) {
  if (!p.isAbsolute(path)) {
    throw const IOSPublicationException(
      "The Firebase receipt directory must be absolute.",
      exitCode: 64,
    );
  }
  final normalized = p.normalize(path);
  if (p.equals(normalized, repositoryRoot) ||
      p.isWithin(repositoryRoot, normalized)) {
    throw const IOSPublicationException(
      "Firebase receipts must be stored outside the Git repository.",
      exitCode: 64,
    );
  }
  final directory = Directory(normalized)..createSync(recursive: true);
  final resolved = directory.resolveSymbolicLinksSync();
  if (p.equals(resolved, repositoryRoot) ||
      p.isWithin(repositoryRoot, resolved)) {
    throw const IOSPublicationException(
      "The Firebase receipt directory resolves inside the Git repository.",
      exitCode: 64,
    );
  }
  _restrictPrivateDirectory(Directory(resolved), label: "receipt");
  return Directory(resolved);
}

Future<PreparedIOSReleaseManifest> loadAndValidatePreparedIOSManifest(
  String manifestPath, {
  required String repositoryRoot,
  required Map<String, String> environment,
}) async {
  if (FileSystemEntity.typeSync(manifestPath, followLinks: false) !=
      FileSystemEntityType.file) {
    throw IOSPublicationException(
      "The prepared manifest is missing or is not a regular file: $manifestPath",
    );
  }
  final manifest = File(manifestPath);
  final resolvedManifestPath = manifest.resolveSymbolicLinksSync();
  _requireOutsideRepository(resolvedManifestPath, repositoryRoot);
  requireReadOnlyIOSReleaseFile(manifest);
  requirePrivateIOSReleaseDirectory(Directory(p.dirname(manifestPath)));

  Map<String, dynamic> root;
  try {
    root = _requireMap(
      jsonDecode(manifest.readAsStringSync()),
      "manifest root",
    );
  } on FormatException catch (error) {
    throw IOSPublicationException("Prepared manifest is invalid JSON: $error");
  }
  if (_requireInt(root, "schemaVersion") !=
      preparation.releaseManifestSchemaVersion) {
    throw const IOSPublicationException(
      "Unsupported prepared-manifest schema version.",
    );
  }
  _requireDateTime(root, "preparedAt");
  final preparationTool = _requireMap(
    root["preparationTool"],
    "preparationTool",
  );
  if (_requireString(preparationTool, "name") !=
          preparation.preparationToolName ||
      _requireString(preparationTool, "version") !=
          preparation.preparationToolVersion) {
    throw const IOSPublicationException(
      "The manifest was not produced by the pinned iOS preparation tool.",
    );
  }
  _requireSha256(preparationTool, "sourceSha256");

  final releaseId = _requireString(root, "releaseId");
  if (!RegExp(r"^[A-Za-z0-9][A-Za-z0-9._-]*$").hasMatch(releaseId)) {
    throw const IOSPublicationException("The manifest releaseId is unsafe.");
  }
  if (p.basename(resolvedManifestPath) != "$releaseId.manifest.json") {
    throw const IOSPublicationException(
      "The manifest filename does not match its releaseId.",
    );
  }

  final artifact = _requireMap(root["artifact"], "artifact");
  final ipaPath = p.normalize(_requireString(artifact, "absolutePath"));
  final ipaFileName = _requireString(artifact, "fileName");
  final ipaSha256 = _requireSha256(artifact, "sha256");
  final ipaSizeBytes = _requireInt(artifact, "sizeBytes");
  if (!p.isAbsolute(ipaPath) || p.basename(ipaPath) != ipaFileName) {
    throw const IOSPublicationException(
      "The manifest IPA path must be absolute and match artifact.fileName.",
    );
  }
  if (ipaFileName != "$releaseId.ipa") {
    throw const IOSPublicationException(
      "The IPA filename does not match the manifest releaseId.",
    );
  }
  if (FileSystemEntity.typeSync(ipaPath, followLinks: false) !=
      FileSystemEntityType.file) {
    throw IOSPublicationException(
      "The prepared IPA is missing or is not a regular file: $ipaPath",
    );
  }
  final ipa = File(ipaPath);
  final resolvedIpaPath = ipa.resolveSymbolicLinksSync();
  _requireOutsideRepository(resolvedIpaPath, repositoryRoot);
  requireReadOnlyIOSReleaseFile(ipa);
  if (!p.equals(p.dirname(resolvedManifestPath), p.dirname(resolvedIpaPath))) {
    throw const IOSPublicationException(
      "The prepared IPA and manifest must remain in the same private directory.",
    );
  }
  if (ipa.lengthSync() != ipaSizeBytes || ipaSizeBytes <= 0) {
    throw const IOSPublicationException(
      "The prepared IPA size differs from the manifest.",
    );
  }

  final source = _requireMap(root["source"], "source");
  final commit = _requireString(source, "commit");
  final sourceRemote = _requireString(source, "remote");
  final sourceCommitUrl = _requireString(source, "commitUrl");
  if (!RegExp(r"^[0-9a-f]{40}$").hasMatch(commit) ||
      !_requireBool(source, "isolatedCheckout") ||
      !_requireBool(source, "checkoutCleanBeforeBuild") ||
      !_requireBool(source, "checkoutCleanAfterAudit")) {
    throw const IOSPublicationException(
      "The manifest must identify one clean isolated source commit.",
    );
  }
  final expectedSourceUrl =
      "${preparation.normalizeGitHubSourceBaseUrl(sourceRemote)}/commit/$commit";
  if (sourceCommitUrl != expectedSourceUrl) {
    throw const IOSPublicationException(
      "The manifest source URL does not exactly match its remote and commit.",
    );
  }

  final build = _requireMap(root["build"], "build");
  if (_requireInt(build, "archiveExportContractVersion") !=
          preparation.archiveExportContractVersion ||
      !_requireBool(build, "rustBindingsGeneratedFromCheckout") ||
      _requireString(build, "scheme") != "selfhosted" ||
      _requireString(build, "configuration") != "Release-selfhosted" ||
      _requireString(build, "exportMethod") != "release-testing") {
    throw const IOSPublicationException(
      "The prepared build metadata does not match the pinned Ad Hoc export contract.",
    );
  }
  final xcodeVersion = _requireString(build, "xcodeVersion");
  final xcodeBuildVersion = _requireString(build, "xcodeBuildVersion");

  final ios = _requireMap(root["ios"], "ios");
  final bundleIdentifier = _requireString(ios, "bundleIdentifier");
  final marketingVersion = _requireString(ios, "marketingVersion");
  final buildNumber = _requireInt(ios, "buildNumber");
  final endpoint = _requireString(ios, "compiledDefaultEndpoint");
  final architectures = _requireStringSet(ios, "architectures");
  final machOCount = _requireInt(ios, "machOCount");
  final extensionCount = _requireInt(ios, "extensionCount");
  final signedEntitlementKeys = _requireStringSet(ios, "signedEntitlementKeys");
  final applicationIdentifier = _requireString(ios, "applicationIdentifier");
  final teamIdentifier = _requireString(ios, "teamIdentifier");
  if (bundleIdentifier != preparation.expectedBundleIdentifier ||
      !RegExp(r"^[0-9]+(?:\.[0-9]+){0,2}$").hasMatch(marketingVersion) ||
      buildNumber <= 0 ||
      _requireString(ios, "buildConfiguration") != "release" ||
      _requireBool(ios, "debuggable") ||
      !_sameSet(architectures, preparation.expectedArchitectures) ||
      machOCount <= 0 ||
      extensionCount != 0 ||
      !_sameSet(
        signedEntitlementKeys,
        preparation.expectedSignedEntitlementKeys,
      ) ||
      !RegExp(r"^[A-Z0-9]{10}$").hasMatch(teamIdentifier) ||
      applicationIdentifier != "$teamIdentifier.$bundleIdentifier") {
    throw const IOSPublicationException(
      "The prepared iOS metadata does not satisfy the pinned release policy.",
    );
  }
  final canonicalEndpoint = preparation.canonicalizeConfigurableEndpoint(
    endpoint,
  );
  if (canonicalEndpoint != endpoint) {
    throw const IOSPublicationException(
      "The manifest endpoint is not canonical.",
    );
  }

  final profile = _requireMap(ios["profile"], "ios.profile");
  final profileName = _requireString(profile, "name");
  final profileUuid = _requireString(profile, "uuid");
  final profileExpiration = _requireDateTime(profile, "expiresAt");
  final authorizedDeviceCount = _requireInt(profile, "authorizedDeviceCount");
  if (!RegExp(
        r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$",
      ).hasMatch(profileUuid) ||
      authorizedDeviceCount <= 0 ||
      !profileExpiration.isAfter(DateTime.now().toUtc())) {
    throw const IOSPublicationException(
      "The prepared provisioning-profile metadata is invalid or expired.",
    );
  }

  final signingCertificate = _requireMap(
    ios["signingCertificate"],
    "ios.signingCertificate",
  );
  final signingCertificateSha256 = _requireSha256(signingCertificate, "sha256");
  final certificateNotBefore = _requireDateTime(
    signingCertificate,
    "notBefore",
  );
  final certificateNotAfter = _requireDateTime(signingCertificate, "notAfter");
  final now = DateTime.now().toUtc();
  if (signingCertificateSha256 !=
          preparation.expectedDistributionCertificateSha256 ||
      certificateNotBefore.isAfter(now) ||
      !certificateNotAfter.isAfter(now)) {
    throw const IOSPublicationException(
      "The prepared signing certificate is not the pinned currently valid certificate.",
    );
  }

  final signature = _requireMap(ios["signature"], "ios.signature");
  final deepSignatureStructureValid = _requireBool(
    signature,
    "deepStructureValid",
  );
  final localTrustChainAccepted = _requireBool(
    signature,
    "localTrustChainAccepted",
  );
  if (!deepSignatureStructureValid) {
    throw const IOSPublicationException(
      "The prepared IPA has no valid deep signature structure.",
    );
  }

  final tools = preparation.IOSReleaseToolPaths.fromEnvironment(environment);
  final auditEnvironment = sanitizedIOSPublicationEnvironment(environment);
  final manifestSha256 = await preparation.sha256File(
    resolvedManifestPath,
    shasum: tools.shasum,
    environment: auditEnvironment,
  );
  final actualIpaSha256 = await preparation.sha256File(
    resolvedIpaPath,
    shasum: tools.shasum,
    environment: auditEnvironment,
  );
  if (actualIpaSha256 != ipaSha256) {
    throw const IOSPublicationException(
      "The prepared IPA SHA-256 differs from the manifest.",
    );
  }

  return PreparedIOSReleaseManifest(
    manifestPath: resolvedManifestPath,
    manifestSha256: manifestSha256,
    releaseId: releaseId,
    ipaPath: resolvedIpaPath,
    ipaSha256: ipaSha256,
    ipaSizeBytes: ipaSizeBytes,
    commit: commit,
    sourceRemote: sourceRemote,
    sourceCommitUrl: sourceCommitUrl,
    bundleIdentifier: bundleIdentifier,
    marketingVersion: marketingVersion,
    buildNumber: buildNumber,
    compiledDefaultEndpoint: canonicalEndpoint,
    architectures: Set<String>.unmodifiable(architectures),
    machOCount: machOCount,
    signedEntitlementKeys: Set<String>.unmodifiable(signedEntitlementKeys),
    applicationIdentifier: applicationIdentifier,
    teamIdentifier: teamIdentifier,
    profileName: profileName,
    profileUuid: profileUuid,
    profileExpiration: profileExpiration,
    authorizedDeviceCount: authorizedDeviceCount,
    signingCertificateSha256: signingCertificateSha256,
    certificateNotBefore: certificateNotBefore,
    certificateNotAfter: certificateNotAfter,
    deepSignatureStructureValid: deepSignatureStructureValid,
    localTrustChainAccepted: localTrustChainAccepted,
    xcodeVersion: xcodeVersion,
    xcodeBuildVersion: xcodeBuildVersion,
  );
}

Future<void> reAuditPreparedIOSIpa(
  PreparedIOSReleaseManifest prepared, {
  required Map<String, String> environment,
}) async {
  final audit = await preparation.auditIOSReleaseIpa(
    ipaPath: prepared.ipaPath,
    canonicalEndpoint: prepared.compiledDefaultEndpoint,
    expectedTeam: prepared.teamIdentifier,
    expectedDeviceCount: prepared.authorizedDeviceCount,
    expectedMarketingVersion: prepared.marketingVersion,
    expectedBuildNumber: prepared.buildNumber,
    tools: preparation.IOSReleaseToolPaths.fromEnvironment(environment),
    processEnvironment: sanitizedIOSPublicationEnvironment(environment),
  );
  if (audit.bundleIdentifier != prepared.bundleIdentifier ||
      audit.marketingVersion != prepared.marketingVersion ||
      audit.buildNumber != prepared.buildNumber ||
      audit.compiledDefaultEndpoint != prepared.compiledDefaultEndpoint ||
      !_sameSet(audit.architectures, prepared.architectures) ||
      audit.machOCount != prepared.machOCount ||
      audit.debuggable ||
      audit.extensionCount != 0 ||
      !_sameSet(audit.signedEntitlementKeys, prepared.signedEntitlementKeys) ||
      audit.applicationIdentifier != prepared.applicationIdentifier ||
      audit.teamIdentifier != prepared.teamIdentifier ||
      audit.profileName != prepared.profileName ||
      audit.profileUuid != prepared.profileUuid ||
      audit.profileExpiration.toUtc() != prepared.profileExpiration.toUtc() ||
      audit.authorizedDeviceCount != prepared.authorizedDeviceCount ||
      audit.signingCertificateSha256 != prepared.signingCertificateSha256 ||
      audit.certificateNotBefore.toUtc() !=
          prepared.certificateNotBefore.toUtc() ||
      audit.certificateNotAfter.toUtc() !=
          prepared.certificateNotAfter.toUtc() ||
      !audit.deepSignatureStructureValid ||
      audit.sha256 != prepared.ipaSha256 ||
      audit.sizeBytes != prepared.ipaSizeBytes) {
    throw const IOSPublicationException(
      "The independent IPA audit differs from the prepared manifest.",
    );
  }
}

void requireReadOnlyIOSReleaseFile(File file) {
  const writePermissionBits = 0x92; // POSIX 0222.
  if (file.statSync().mode & writePermissionBits != 0) {
    throw IOSPublicationException(
      "Prepared release file is writable: ${file.path}",
    );
  }
}

void requirePrivateIOSReleaseDirectory(Directory directory) {
  if (!directory.existsSync()) {
    throw IOSPublicationException(
      "Prepared release directory does not exist: ${directory.path}",
    );
  }
  final resolved = Directory(directory.resolveSymbolicLinksSync());
  if ((resolved.statSync().mode & 0x1ff) != 0x1c0) {
    throw IOSPublicationException(
      "Prepared release directory must be mode 0700: ${resolved.path}",
    );
  }
}

String readOptionalIOSReleaseNotes(String? path) {
  if (path == null) {
    return "";
  }
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw IOSPublicationException(
      "Release-notes file does not exist as a regular file: $path",
    );
  }
  final value = File(path).readAsStringSync().trim();
  if (value.contains("\u0000")) {
    throw const IOSPublicationException("Release notes contain a NUL byte.");
  }
  return value;
}

String buildFirebaseIOSReleaseNotes(
  PreparedIOSReleaseManifest prepared, {
  String operatorNotes = "",
}) {
  final sourceBase = prepared.sourceCommitUrl.substring(
    0,
    prepared.sourceCommitUrl.length - "/commit/${prepared.commit}".length,
  );
  final sections = <String>[
    "Ente Photos Self-Hosted iOS ${prepared.marketingVersion} "
        "(${prepared.buildNumber})",
    "Prepared release: ${prepared.releaseId}\n"
        "IPA SHA-256: ${prepared.ipaSha256}\n"
        "Source code (AGPL-3.0): ${prepared.sourceCommitUrl}\n"
        "Build instructions: $sourceBase/blob/${prepared.commit}/mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md",
    if (operatorNotes.trim().isNotEmpty) operatorNotes.trim(),
  ];
  final notes = "${sections.join("\n\n")}\n";
  if (prepared.sourceCommitUrl.allMatches(notes).length != 1) {
    throw const IOSPublicationException(
      "Release notes must contain the exact source commit URL once.",
    );
  }
  if (utf8.encode(notes).length > _maximumReleaseNotesBytes) {
    throw const IOSPublicationException(
      "Release notes exceed $_maximumReleaseNotesBytes UTF-8 bytes.",
    );
  }
  return notes;
}

Map<String, dynamic> decodeFirebaseIOSCliSuccess(String stdoutValue) {
  Object? decoded;
  try {
    decoded = jsonDecode(stdoutValue);
  } on FormatException catch (error) {
    throw IOSPublicationException("Firebase CLI returned invalid JSON: $error");
  }
  final root = _requireMap(decoded, "Firebase CLI response");
  if (root["status"] != "success") {
    throw const IOSPublicationException("Firebase CLI did not report success.");
  }
  return root;
}

Map<String, dynamic> validateFirebaseIOSApp(
  Map<String, dynamic> response, {
  required String projectId,
  required String appId,
  required String expectedBundleIdentifier,
}) {
  final result = response["result"];
  if (result is! List) {
    throw const IOSPublicationException(
      "Firebase app-list response has no result list.",
    );
  }
  final matches = result
      .map((value) => _requireMap(value, "Firebase iOS app"))
      .where((app) => app["appId"] == appId)
      .toList();
  if (matches.length != 1) {
    throw IOSPublicationException(
      "Expected exactly one active Firebase iOS app with ID $appId.",
    );
  }
  final app = matches.single;
  if (app["projectId"] != projectId ||
      app["platform"] != "IOS" ||
      app["state"] != "ACTIVE" ||
      app["bundleId"] != expectedBundleIdentifier) {
    throw IOSPublicationException(
      "Firebase app $appId is not the active $expectedBundleIdentifier iOS "
      "registration in project $projectId.",
    );
  }
  return app;
}

Map<String, dynamic> validateFirebaseIOSGroup(
  Map<String, dynamic> response, {
  required String expectedAlias,
}) {
  final result = _requireMap(response["result"], "Firebase group result");
  final groupsValue = result["groups"];
  if (groupsValue is! List) {
    throw const IOSPublicationException(
      "Firebase group-list response has no groups list.",
    );
  }
  final matches = groupsValue
      .map((value) => _requireMap(value, "Firebase group"))
      .where((group) {
        final name = group["name"];
        return name is String && name.endsWith("/groups/$expectedAlias");
      })
      .toList();
  if (matches.length != 1) {
    throw IOSPublicationException(
      "Expected exactly one Firebase App Distribution group named "
      "'$expectedAlias'.",
    );
  }
  _requireString(matches.single, "displayName");
  return matches.single;
}

FirebaseIOSReleaseReferences parseFirebaseIOSReleaseReferences(String output) {
  final plain = output.replaceAll(RegExp(r"\x1B\[[0-?]*[ -/]*[@-~]"), "");
  String capture(RegExp expression, String label) {
    final match = expression.firstMatch(plain);
    if (match == null) {
      throw IOSPublicationException(
        "Firebase did not return the $label release reference.",
      );
    }
    final uri = Uri.tryParse(match.group(1)!);
    if (uri == null || uri.scheme != "https" || uri.host.isEmpty) {
      throw IOSPublicationException(
        "Firebase returned an invalid $label release reference.",
      );
    }
    return uri.toString();
  }

  var disposition = "UNKNOWN";
  if (plain.contains("uploaded new release")) {
    disposition = "RELEASE_CREATED";
  } else if (plain.contains("uploaded update to existing release")) {
    disposition = "RELEASE_UPDATED";
  } else if (plain.contains("re-uploaded already existing release")) {
    disposition = "RELEASE_UNMODIFIED";
  }
  return FirebaseIOSReleaseReferences(
    firebaseConsoleUri: capture(
      RegExp(r"View this release in the Firebase console:\s*(https://\S+)"),
      "console",
    ),
    testingUri: capture(
      RegExp(
        r"Share this release with testers who have access:\s*(https://\S+)",
      ),
      "tester",
    ),
    binaryDownloadUri: capture(
      RegExp(
        r"Download the release binary \(link expires in 1 hour\):\s*(https://\S+)",
      ),
      "binary-download",
    ),
    uploadDisposition: disposition,
  );
}

String confirmationForIOSRelease(String releaseId) => "PUBLISH $releaseId";

void requireExactIOSConfirmation(String? actual, String expected) {
  if (actual != expected) {
    throw const IOSPublicationException(
      "Publication confirmation did not match; nothing was uploaded.",
      exitCode: 64,
    );
  }
}

Map<String, String> sanitizedIOSPublicationEnvironment(
  Map<String, String> environment,
) {
  const exactCredentialKeys = <String>{
    "FIREBASE_TOKEN",
    "GOOGLE_APPLICATION_CREDENTIALS",
    "GOOGLE_APPLICATION_CREDENTIALS_JSON",
    "GOOGLE_CREDENTIALS",
    "GCLOUD_SERVICE_KEY",
    "CLOUDSDK_AUTH_ACCESS_TOKEN",
    "GOOGLE_OAUTH_ACCESS_TOKEN",
    "GOOGLE_GHA_CREDS_PATH",
    "SSH_AUTH_SOCK",
    "DEVELOPMENT_TEAM",
    "CODE_SIGN_IDENTITY",
    "PROVISIONING_PROFILE_SPECIFIER",
    "APPLE_ID",
    "APPLE_APP_SPECIFIC_PASSWORD",
  };
  return Map<String, String>.unmodifiable(
    Map<String, String>.fromEntries(
      environment.entries.where((entry) {
        final key = entry.key.toUpperCase();
        return !exactCredentialKeys.contains(key) &&
            !key.startsWith("ENTE_FIREBASE_") &&
            !key.startsWith("ENTE_IOS_") &&
            !key.startsWith("FASTLANE_") &&
            !key.startsWith("MATCH_") &&
            !key.startsWith("APP_STORE_CONNECT_") &&
            !key.startsWith("ASC_") &&
            !key.startsWith("AWS_") &&
            !key.startsWith("AZURE_") &&
            !key.contains("PASSWORD") &&
            !key.contains("PRIVATE_KEY") &&
            !key.contains("SECRET") &&
            !key.endsWith("_TOKEN") &&
            !key.endsWith("_CREDENTIALS");
      }),
    ),
  );
}

String resolveFirebaseIOSExecutable(Map<String, String> environment) {
  final configured = environment["FIREBASE_CLI"];
  if (configured != null && configured.trim().isNotEmpty) {
    final file = File(configured);
    if (!p.isAbsolute(configured) ||
        FileSystemEntity.typeSync(configured, followLinks: true) !=
            FileSystemEntityType.file) {
      throw const IOSPublicationException(
        "FIREBASE_CLI must name an existing absolute executable.",
        exitCode: 69,
      );
    }
    return file.resolveSymbolicLinksSync();
  }
  final pathValue = environment["PATH"] ?? "";
  for (final directory in pathValue.split(Platform.isWindows ? ";" : ":")) {
    if (directory.isEmpty) {
      continue;
    }
    final candidate = File(p.join(directory, "firebase"));
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }
  throw const IOSPublicationException(
    "Firebase CLI was not found; set FIREBASE_CLI or add firebase to PATH.",
    exitCode: 69,
  );
}

void validateIOSPublicationVersionLedger(
  String receiptDirectory, {
  required String firebaseAppId,
  required String bundleIdentifier,
  required int buildNumber,
}) {
  int? highestBuildNumber;
  String? highestReceipt;
  final receipts = Directory(receiptDirectory)
      .listSync(followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith(".firebase-ios-release.json"));
  for (final receipt in receipts) {
    if (FileSystemEntity.typeSync(receipt.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw IOSPublicationException(
        "Publication receipt is not a regular file: ${receipt.path}",
      );
    }
    requireReadOnlyIOSReleaseFile(receipt);
    Map<String, dynamic> root;
    try {
      root = _requireMap(
        jsonDecode(receipt.readAsStringSync()),
        "publication receipt",
      );
    } on Object catch (error) {
      throw IOSPublicationException(
        "Cannot validate prior publication receipt ${receipt.path}: $error",
      );
    }
    if (_requireInt(root, "schemaVersion") != publicationReceiptSchemaVersion) {
      throw IOSPublicationException(
        "Unsupported prior publication receipt: ${receipt.path}",
      );
    }
    final firebase = _requireMap(root["firebase"], "firebase");
    final ios = _requireMap(root["ios"], "ios");
    if (firebase["appId"] != firebaseAppId ||
        ios["bundleIdentifier"] != bundleIdentifier) {
      continue;
    }
    final priorBuildNumber = _requireInt(ios, "buildNumber");
    if (highestBuildNumber == null || priorBuildNumber > highestBuildNumber) {
      highestBuildNumber = priorBuildNumber;
      highestReceipt = receipt.path;
    }
  }
  if (highestBuildNumber != null && buildNumber <= highestBuildNumber) {
    throw IOSPublicationException(
      "Build number $buildNumber is not greater than guarded Firebase iOS "
      "release $highestBuildNumber recorded in $highestReceipt.",
    );
  }
}

Map<String, Object?> buildSuccessfulIOSPublicationReceipt({
  required PreparedIOSReleaseManifest prepared,
  required FirebaseIOSRegistration registration,
  required String releaseNotes,
  required FirebaseIOSReleaseReferences references,
}) => <String, Object?>{
  "schemaVersion": publicationReceiptSchemaVersion,
  "publicationTool": <String, Object?>{
    "name": publicationToolName,
    "version": publicationToolVersion,
  },
  "status": "published",
  "publishedAt": DateTime.now().toUtc().toIso8601String(),
  "releaseId": prepared.releaseId,
  "preparedManifest": <String, Object?>{
    "absolutePath": prepared.manifestPath,
    "sha256": prepared.manifestSha256,
  },
  "artifact": <String, Object?>{
    "absolutePath": prepared.ipaPath,
    "sha256": prepared.ipaSha256,
    "sizeBytes": prepared.ipaSizeBytes,
  },
  "source": <String, Object?>{
    "commit": prepared.commit,
    "commitUrl": prepared.sourceCommitUrl,
  },
  "ios": <String, Object?>{
    "bundleIdentifier": prepared.bundleIdentifier,
    "marketingVersion": prepared.marketingVersion,
    "buildNumber": prepared.buildNumber,
    "compiledDefaultEndpoint": prepared.compiledDefaultEndpoint,
    "architectures": prepared.architectures.toList()..sort(),
    "machOCount": prepared.machOCount,
    "applicationIdentifier": prepared.applicationIdentifier,
    "teamIdentifier": prepared.teamIdentifier,
    "profile": <String, Object?>{
      "name": prepared.profileName,
      "uuid": prepared.profileUuid,
      "expiresAt": prepared.profileExpiration.toUtc().toIso8601String(),
      "authorizedDeviceCount": prepared.authorizedDeviceCount,
    },
    "signingCertificate": <String, Object?>{
      "sha256": prepared.signingCertificateSha256,
      "notBefore": prepared.certificateNotBefore.toUtc().toIso8601String(),
      "notAfter": prepared.certificateNotAfter.toUtc().toIso8601String(),
    },
  },
  "firebase": <String, Object?>{
    "projectId": registration.projectId,
    "appId": registration.appId,
    "registeredBundleIdentifier": registration.bundleIdentifier,
    "groupAlias": trustedIOSTesterGroupAlias,
    "groupName": registration.groupName,
    "groupDisplayName": registration.groupDisplayName,
    "uploadDisposition": references.uploadDisposition,
    "firebaseConsoleUri": references.firebaseConsoleUri,
    "testingUri": references.testingUri,
    "binaryDownloadUri": references.binaryDownloadUri,
    "binaryDownloadUriExpiry":
        "Firebase CLI reports that this link expires in 1 hour.",
  },
  "releaseNotes": releaseNotes,
};

String writeFailedIOSPublicationAttempt(
  String receiptDirectory, {
  required PreparedIOSReleaseManifest prepared,
  required FirebaseIOSRegistration registration,
  required String releaseNotes,
  required int firebaseExitCode,
  required String firebaseOutput,
}) {
  final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r"[^0-9A-Za-z]"),
    "",
  );
  var attemptPath = p.join(
    receiptDirectory,
    "${prepared.releaseId}.firebase-ios-attempt-$timestamp.json",
  );
  var suffix = 1;
  while (File(attemptPath).existsSync()) {
    attemptPath = p.join(
      receiptDirectory,
      "${prepared.releaseId}.firebase-ios-attempt-$timestamp-$suffix.json",
    );
    suffix++;
  }
  writeImmutableIOSJson(attemptPath, <String, Object?>{
    "schemaVersion": publicationReceiptSchemaVersion,
    "publicationTool": <String, Object?>{
      "name": publicationToolName,
      "version": publicationToolVersion,
    },
    "status": "failed-or-partial",
    "attemptedAt": DateTime.now().toUtc().toIso8601String(),
    "releaseId": prepared.releaseId,
    "preparedManifest": <String, Object?>{
      "absolutePath": prepared.manifestPath,
      "sha256": prepared.manifestSha256,
    },
    "artifact": <String, Object?>{
      "absolutePath": prepared.ipaPath,
      "sha256": prepared.ipaSha256,
    },
    "source": <String, Object?>{
      "commit": prepared.commit,
      "commitUrl": prepared.sourceCommitUrl,
    },
    "ios": <String, Object?>{
      "bundleIdentifier": prepared.bundleIdentifier,
      "marketingVersion": prepared.marketingVersion,
      "buildNumber": prepared.buildNumber,
      "teamIdentifier": prepared.teamIdentifier,
    },
    "firebase": <String, Object?>{
      "projectId": registration.projectId,
      "appId": registration.appId,
      "groupAlias": trustedIOSTesterGroupAlias,
      "exitCode": firebaseExitCode,
      "output": firebaseOutput,
    },
    "releaseNotes": releaseNotes,
    "recovery":
        "Inspect Firebase App Distribution before retrying; an upload may have occurred.",
  });
  return attemptPath;
}

void writeImmutableIOSJson(String finalPath, Map<String, Object?> value) {
  if (File(finalPath).existsSync()) {
    throw IOSPublicationException(
      "Refusing to overwrite existing publication record: $finalPath",
      exitCode: 73,
    );
  }
  final parent = Directory(p.dirname(finalPath));
  if (!parent.existsSync()) {
    throw IOSPublicationException(
      "Publication record directory does not exist: ${parent.path}",
      exitCode: 73,
    );
  }
  requirePrivateIOSReleaseDirectory(parent);
  final staging = parent.createTempSync(".firebase-ios-receipt-");
  var linked = false;
  try {
    final staged = File(p.join(staging.path, p.basename(finalPath)))
      ..writeAsStringSync(
        "${const JsonEncoder.withIndent("  ").convert(value)}\n",
        flush: true,
      );
    final chmod = Process.runSync("chmod", ["0444", staged.path]);
    if (chmod.exitCode != 0) {
      throw const IOSPublicationException(
        "Could not make the publication record read-only.",
        exitCode: 73,
      );
    }
    final link = Process.runSync("ln", [staged.path, finalPath]);
    if (link.exitCode != 0) {
      throw IOSPublicationException(
        "Could not finalize the publication record without overwrite: "
        "${(link.stderr as String).trim()}",
        exitCode: 73,
      );
    }
    linked = true;
  } finally {
    if (!linked && File(finalPath).existsSync()) {
      File(finalPath).deleteSync();
    }
    if (staging.existsSync()) {
      staging.deleteSync(recursive: true);
    }
  }
}

void requireSamePreparedIOSRelease(
  PreparedIOSReleaseManifest before,
  PreparedIOSReleaseManifest after,
) {
  if (before.manifestSha256 != after.manifestSha256 ||
      before.ipaSha256 != after.ipaSha256 ||
      before.ipaSizeBytes != after.ipaSizeBytes ||
      before.releaseId != after.releaseId) {
    throw const IOSPublicationException(
      "The prepared iOS release changed after confirmation; nothing was uploaded.",
    );
  }
}

void printIOSPublicationSummary(
  PreparedIOSReleaseManifest prepared,
  FirebaseIOSRegistration registration, {
  required String receiptDirectory,
  required bool preflightOnly,
}) {
  stdout.writeln();
  stdout.writeln(
    "Guarded Firebase iOS publication "
    "${preflightOnly ? "preflight" : "summary"}:",
  );
  stdout.writeln("  Release: ${prepared.releaseId}");
  stdout.writeln("  IPA: ${prepared.ipaPath}");
  stdout.writeln("  SHA-256: ${prepared.ipaSha256}");
  stdout.writeln(
    "  iOS: ${prepared.bundleIdentifier} ${prepared.marketingVersion} "
    "(${prepared.buildNumber})",
  );
  stdout.writeln("  Server: ${prepared.compiledDefaultEndpoint}");
  stdout.writeln("  Architectures: ${_sorted(prepared.architectures)}");
  stdout.writeln("  Profile devices: ${prepared.authorizedDeviceCount}");
  stdout.writeln("  Signing certificate: ${prepared.signingCertificateSha256}");
  stdout.writeln("  Apple team: verified (identifier not displayed)");
  stdout.writeln("  Source: ${prepared.sourceCommitUrl}");
  stdout.writeln("  Firebase project: ${registration.projectId}");
  stdout.writeln("  Firebase app: ${registration.appId}");
  stdout.writeln(
    "  Firebase group: $trustedIOSTesterGroupAlias "
    "(${registration.groupDisplayName})",
  );
  stdout.writeln("  Receipt directory: $receiptDirectory");
}

void _restrictPrivateDirectory(Directory directory, {required String label}) {
  final result = Process.runSync("chmod", ["0700", directory.path]);
  if (result.exitCode != 0 || (directory.statSync().mode & 0x1ff) != 0x1c0) {
    throw IOSPublicationException(
      "The Firebase $label directory could not be restricted to mode 0700.",
      exitCode: 73,
    );
  }
}

void _requireOutsideRepository(String path, String repositoryRoot) {
  if (p.equals(path, repositoryRoot) || p.isWithin(repositoryRoot, path)) {
    throw const IOSPublicationException(
      "Prepared release files must remain outside the Git repository.",
    );
  }
}

Map<String, dynamic> _requireMap(Object? value, String label) {
  if (value is! Map) {
    throw IOSPublicationException("Expected $label to be a JSON object.");
  }
  try {
    return Map<String, dynamic>.from(value);
  } on Object {
    throw IOSPublicationException("Expected $label to use string JSON keys.");
  }
}

String _requireString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw IOSPublicationException("Expected '$key' to be a non-empty string.");
  }
  return value;
}

String _requireSha256(Map<String, dynamic> map, String key) {
  final value = _requireString(map, key).toLowerCase();
  if (!RegExp(r"^[0-9a-f]{64}$").hasMatch(value)) {
    throw IOSPublicationException("Expected '$key' to be a SHA-256 value.");
  }
  return value;
}

int _requireInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw IOSPublicationException("Expected '$key' to be an integer.");
  }
  return value;
}

bool _requireBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! bool) {
    throw IOSPublicationException("Expected '$key' to be a boolean.");
  }
  return value;
}

DateTime _requireDateTime(Map<String, dynamic> map, String key) {
  final value = _requireString(map, key);
  final parsed = DateTime.tryParse(value)?.toUtc();
  if (parsed == null || !value.endsWith("Z")) {
    throw IOSPublicationException(
      "Expected '$key' to be one UTC ISO-8601 timestamp.",
    );
  }
  return parsed;
}

Set<String> _requireStringSet(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List || value.any((element) => element is! String)) {
    throw IOSPublicationException("Expected '$key' to be a string list.");
  }
  final result = value.cast<String>().toSet();
  if (result.length != value.length) {
    throw IOSPublicationException("Expected '$key' to contain no duplicates.");
  }
  return result;
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

String _sorted(Set<String> values) {
  final sorted = values.toList()..sort();
  return sorted.join(", ");
}

String _firebaseFailureDetails(
  ProcessResult result, {
  required String fallback,
}) {
  final details = [
    result.stderr as String,
    result.stdout as String,
  ].map((value) => value.trim()).where((value) => value.isNotEmpty).join("\n");
  return details.isEmpty ? fallback : "$fallback\n$details";
}
