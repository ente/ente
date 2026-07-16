import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;

import "prepare_self_hosted_android_release.dart" as preparation;

const publicationToolName = "ente-self-hosted-android-firebase-publisher";
const publicationToolVersion = "1.0.0";
const publicationReceiptSchemaVersion = 1;
const trustedTesterGroupAlias = "trusted-testers";
const _maximumReleaseNotesBytes = 10000;

const _usage =
    """
Publish one prepared Ente Photos Android release to Firebase App Distribution.

Usage:
  ./scripts/publish_self_hosted_android_release.sh \\
    --manifest /absolute/path/release.manifest.json \\
    --receipt-dir /absolute/path/firebase-receipts \\
    --firebase-project your-project-id \\
    --firebase-app 1:1234567890:android:opaque-id

Options:
  --release-notes-file PATH  Append operator notes to the generated audit notes.
  --preflight-only           Verify everything without prompting or uploading.
  -h, --help                 Show this help.

Environment alternatives:
  ENTE_ANDROID_RELEASE_MANIFEST
  ENTE_FIREBASE_RELEASE_RECEIPT_DIR
  ENTE_FIREBASE_PROJECT_ID
  ENTE_FIREBASE_ANDROID_APP_ID
  FIREBASE_CLI                       Firebase executable; otherwise use PATH.

The Firebase group is pinned to '$trustedTesterGroupAlias'. Publishing requires
typing the exact release-specific confirmation shown after all checks pass.
""";

Future<void> main(List<String> arguments) async {
  try {
    final options = PublicationOptions.parse(
      arguments,
      environment: Platform.environment,
    );
    if (options.showHelp) {
      stdout.write(_usage);
      return;
    }

    final result = await publishSelfHostedAndroidRelease(options);
    if (result == null) {
      return;
    }
    stdout.writeln();
    stdout.writeln("Firebase publication completed:");
    stdout.writeln("  Receipt: ${result.receiptPath}");
    stdout.writeln("  Console: ${result.references.firebaseConsoleUri}");
    stdout.writeln("  Tester: ${result.references.testingUri}");
    stdout.writeln(
      "  Binary: ${result.references.binaryDownloadUri} (expires in 1 hour)",
    );
  } on PublicationException catch (error) {
    stderr.writeln("Firebase publication failed: ${error.message}");
    exitCode = error.exitCode;
  } on Object catch (error) {
    stderr.writeln("Firebase publication failed unexpectedly: $error");
    exitCode = 70;
  }
}

class PublicationOptions {
  const PublicationOptions({
    required this.manifestPath,
    required this.receiptDirectory,
    required this.firebaseProjectId,
    required this.firebaseAppId,
    required this.environment,
    this.releaseNotesFile,
    this.preflightOnly = false,
    this.showHelp = false,
  });

  factory PublicationOptions.parse(
    List<String> arguments, {
    required Map<String, String> environment,
  }) {
    if (arguments.length == 1 &&
        (arguments.single == "--help" || arguments.single == "-h")) {
      return PublicationOptions(
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
          throw PublicationException("$name requires a value.", exitCode: 64);
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
        throw PublicationException(
          "Unknown argument '$argument'.\n\n$_usage",
          exitCode: 64,
        );
      }
    }

    manifestPath ??= environment["ENTE_ANDROID_RELEASE_MANIFEST"];
    receiptDirectory ??= environment["ENTE_FIREBASE_RELEASE_RECEIPT_DIR"];
    firebaseProjectId ??= environment["ENTE_FIREBASE_PROJECT_ID"];
    firebaseAppId ??= environment["ENTE_FIREBASE_ANDROID_APP_ID"];

    final requiredValues = <String, String?>{
      "--manifest or ENTE_ANDROID_RELEASE_MANIFEST": manifestPath,
      "--receipt-dir or ENTE_FIREBASE_RELEASE_RECEIPT_DIR": receiptDirectory,
      "--firebase-project or ENTE_FIREBASE_PROJECT_ID": firebaseProjectId,
      "--firebase-app or ENTE_FIREBASE_ANDROID_APP_ID": firebaseAppId,
    };
    for (final entry in requiredValues.entries) {
      if (entry.value == null || entry.value!.trim().isEmpty) {
        throw PublicationException("Provide ${entry.key}.", exitCode: 64);
      }
    }

    manifestPath = p.normalize(manifestPath!);
    receiptDirectory = p.normalize(receiptDirectory!);
    if (!p.isAbsolute(manifestPath)) {
      throw const PublicationException(
        "The prepared manifest path must be absolute.",
        exitCode: 64,
      );
    }
    if (!p.isAbsolute(receiptDirectory)) {
      throw const PublicationException(
        "The Firebase receipt directory must be absolute.",
        exitCode: 64,
      );
    }
    if (releaseNotesFile != null) {
      releaseNotesFile = p.normalize(releaseNotesFile);
      if (!p.isAbsolute(releaseNotesFile)) {
        throw const PublicationException(
          "The release-notes file path must be absolute.",
          exitCode: 64,
        );
      }
    }
    if (firebaseProjectId!.startsWith("-") || firebaseAppId!.startsWith("-")) {
      throw const PublicationException(
        "Firebase identifiers cannot start with '-'.",
        exitCode: 64,
      );
    }

    return PublicationOptions(
      manifestPath: manifestPath,
      receiptDirectory: receiptDirectory,
      firebaseProjectId: firebaseProjectId.trim(),
      firebaseAppId: firebaseAppId.trim(),
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

class PublicationException implements Exception {
  const PublicationException(this.message, {this.exitCode = 66});

  final String message;
  final int exitCode;

  @override
  String toString() => message;
}

class PreparedReleaseManifest {
  const PreparedReleaseManifest({
    required this.manifestPath,
    required this.manifestSha256,
    required this.releaseId,
    required this.apkPath,
    required this.apkSha256,
    required this.apkSizeBytes,
    required this.commit,
    required this.sourceRemote,
    required this.sourceCommitUrl,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.minSdk,
    required this.targetSdk,
    required this.compileSdk,
    required this.abis,
    required this.compiledDefaultEndpoint,
    required this.signingCertificateSha256,
    required this.signatureSchemes,
  });

  final String manifestPath;
  final String manifestSha256;
  final String releaseId;
  final String apkPath;
  final String apkSha256;
  final int apkSizeBytes;
  final String commit;
  final String sourceRemote;
  final String sourceCommitUrl;
  final String packageName;
  final String versionName;
  final int versionCode;
  final int minSdk;
  final int targetSdk;
  final int compileSdk;
  final Set<String> abis;
  final String compiledDefaultEndpoint;
  final String signingCertificateSha256;
  final Map<String, bool> signatureSchemes;
}

class FirebaseRegistration {
  const FirebaseRegistration({
    required this.projectId,
    required this.appId,
    required this.packageName,
    required this.groupName,
    required this.groupDisplayName,
  });

  final String projectId;
  final String appId;
  final String packageName;
  final String groupName;
  final String groupDisplayName;
}

class FirebaseReleaseReferences {
  const FirebaseReleaseReferences({
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

class PublicationResult {
  const PublicationResult({
    required this.receiptPath,
    required this.references,
  });

  final String receiptPath;
  final FirebaseReleaseReferences references;
}

typedef PublicationProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

Future<ProcessResult> runPublicationProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

class FirebaseCliClient {
  FirebaseCliClient({
    required this.executable,
    required this.projectId,
    required this.workingDirectory,
    required Map<String, String> environment,
    this.runner = runPublicationProcess,
  }) : environment = sanitizedPublicationEnvironment(environment);

  final String executable;
  final String projectId;
  final String workingDirectory;
  final Map<String, String> environment;
  final PublicationProcessRunner runner;

  Future<FirebaseRegistration> verifyRegistration({
    required String appId,
    required String expectedPackageName,
  }) async {
    final appsResult = await _runJson([
      "apps:list",
      "ANDROID",
      "--project",
      projectId,
      "--json",
      "--non-interactive",
    ], "Could not list Firebase Android apps.");
    final app = validateFirebaseAndroidApp(
      appsResult,
      projectId: projectId,
      appId: appId,
      expectedPackageName: expectedPackageName,
    );

    final groupsResult = await _runJson([
      "appdistribution:groups:list",
      "--project",
      projectId,
      "--json",
      "--non-interactive",
    ], "Could not list Firebase App Distribution groups.");
    final group = validateFirebaseGroup(
      groupsResult,
      expectedAlias: trustedTesterGroupAlias,
    );

    return FirebaseRegistration(
      projectId: app["projectId"]! as String,
      appId: app["appId"]! as String,
      packageName: app["packageName"]! as String,
      groupName: group["name"]! as String,
      groupDisplayName: group["displayName"]! as String,
    );
  }

  Future<ProcessResult> distribute({
    required String apkPath,
    required String appId,
    required String releaseNotesFile,
  }) => runner(
    executable,
    [
      "appdistribution:distribute",
      apkPath,
      "--app",
      appId,
      "--groups",
      trustedTesterGroupAlias,
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
      throw PublicationException(
        "$failureMessage ${error.message}",
        exitCode: 69,
      );
    }
    if (result.exitCode != 0) {
      throw PublicationException(
        _firebaseFailureDetails(result, fallback: failureMessage),
        exitCode: 69,
      );
    }
    return decodeFirebaseCliSuccess(result.stdout as String);
  }
}

Future<PublicationResult?> publishSelfHostedAndroidRelease(
  PublicationOptions options, {
  PublicationProcessRunner processRunner = runPublicationProcess,
  String? Function()? readConfirmation,
}) async {
  final appDirectory = p.dirname(p.dirname(Platform.script.toFilePath()));
  final repositoryRoot = Directory(
    p.dirname(p.dirname(p.dirname(appDirectory))),
  ).resolveSymbolicLinksSync();
  final receiptDirectory = prepareExternalReceiptDirectory(
    options.receiptDirectory,
    repositoryRoot: repositoryRoot,
  );
  final firebaseWorkingDirectory = receiptDirectory.createTempSync(
    ".firebase-publication-",
  );

  try {
    final firebaseExecutable = resolveFirebaseExecutable(options.environment);
    final firebase = FirebaseCliClient(
      executable: firebaseExecutable,
      projectId: options.firebaseProjectId,
      workingDirectory: firebaseWorkingDirectory.path,
      environment: options.environment,
      runner: processRunner,
    );
    var prepared = await loadAndValidatePreparedManifest(
      options.manifestPath,
      repositoryRoot: repositoryRoot,
      environment: options.environment,
    );
    await reAuditPreparedApk(prepared, environment: options.environment);
    validatePublicationVersionLedger(
      receiptDirectory.path,
      firebaseAppId: options.firebaseAppId,
      packageName: prepared.packageName,
      versionCode: prepared.versionCode,
    );
    final releaseNotes = buildFirebaseReleaseNotes(
      prepared,
      operatorNotes: readOptionalReleaseNotes(options.releaseNotesFile),
    );
    var registration = await firebase.verifyRegistration(
      appId: options.firebaseAppId,
      expectedPackageName: prepared.packageName,
    );

    printPublicationSummary(
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

    final expectedConfirmation = confirmationFor(prepared.releaseId);
    stdout.writeln();
    stdout.writeln("This will upload and notify '$trustedTesterGroupAlias'.");
    stdout.write("Type '$expectedConfirmation' to continue: ");
    final actualConfirmation = readConfirmation?.call() ?? stdin.readLineSync();
    requireExactConfirmation(actualConfirmation, expectedConfirmation);

    // Close the confirmation race: independently re-read/re-audit the files and
    // re-query Firebase immediately before the only mutating subprocess.
    final confirmedPrepared = await loadAndValidatePreparedManifest(
      options.manifestPath,
      repositoryRoot: repositoryRoot,
      environment: options.environment,
    );
    await reAuditPreparedApk(
      confirmedPrepared,
      environment: options.environment,
    );
    requireSamePreparedRelease(prepared, confirmedPrepared);
    prepared = confirmedPrepared;
    registration = await firebase.verifyRegistration(
      appId: options.firebaseAppId,
      expectedPackageName: prepared.packageName,
    );

    final finalReceiptPath = p.join(
      receiptDirectory.path,
      "${prepared.releaseId}.firebase-release.json",
    );
    if (File(finalReceiptPath).existsSync()) {
      throw PublicationException(
        "A Firebase receipt already exists for this release: $finalReceiptPath",
        exitCode: 73,
      );
    }
    final notesFile = File(
      p.join(firebaseWorkingDirectory.path, "release-notes.txt"),
    )..writeAsStringSync(releaseNotes, flush: true);

    stdout.writeln();
    stdout.writeln("Uploading the unchanged audited APK to Firebase...");
    ProcessResult upload;
    try {
      upload = await firebase.distribute(
        apkPath: prepared.apkPath,
        appId: options.firebaseAppId,
        releaseNotesFile: notesFile.path,
      );
    } on ProcessException catch (error) {
      final attemptPath = writeFailedPublicationAttempt(
        receiptDirectory.path,
        prepared: prepared,
        registration: registration,
        releaseNotes: releaseNotes,
        firebaseExitCode: 69,
        firebaseOutput: error.message,
      );
      throw PublicationException(
        "Firebase could not be started. The attempt record is $attemptPath",
        exitCode: 69,
      );
    }

    final firebaseOutput = [
      upload.stdout as String,
      upload.stderr as String,
    ].where((value) => value.trim().isNotEmpty).join("\n");
    if (upload.exitCode != 0) {
      final attemptPath = writeFailedPublicationAttempt(
        receiptDirectory.path,
        prepared: prepared,
        registration: registration,
        releaseNotes: releaseNotes,
        firebaseExitCode: upload.exitCode,
        firebaseOutput: firebaseOutput,
      );
      throw PublicationException(
        "${_firebaseFailureDetails(upload, fallback: "Firebase rejected the publication.")}\n"
        "An upload may have occurred before the failure. Inspect Firebase before retrying. "
        "Attempt record: $attemptPath",
        exitCode: 69,
      );
    }

    FirebaseReleaseReferences references;
    try {
      references = parseFirebaseReleaseReferences(firebaseOutput);
    } on PublicationException catch (error) {
      final attemptPath = writeFailedPublicationAttempt(
        receiptDirectory.path,
        prepared: prepared,
        registration: registration,
        releaseNotes: releaseNotes,
        firebaseExitCode: upload.exitCode,
        firebaseOutput: firebaseOutput,
      );
      throw PublicationException(
        "${error.message} Firebase reported success, so do not retry before "
        "checking the console. Attempt record: $attemptPath",
        exitCode: 69,
      );
    }

    final receipt = buildSuccessfulPublicationReceipt(
      prepared: prepared,
      registration: registration,
      releaseNotes: releaseNotes,
      references: references,
    );
    writeImmutableJson(finalReceiptPath, receipt);
    return PublicationResult(
      receiptPath: finalReceiptPath,
      references: references,
    );
  } finally {
    if (firebaseWorkingDirectory.existsSync()) {
      firebaseWorkingDirectory.deleteSync(recursive: true);
    }
  }
}

Directory prepareExternalReceiptDirectory(
  String path, {
  required String repositoryRoot,
}) {
  if (!p.isAbsolute(path)) {
    throw const PublicationException(
      "The Firebase receipt directory must be absolute.",
      exitCode: 64,
    );
  }
  final normalized = p.normalize(path);
  if (p.equals(normalized, repositoryRoot) ||
      p.isWithin(repositoryRoot, normalized)) {
    throw const PublicationException(
      "Firebase receipts must be stored outside the Git repository.",
      exitCode: 64,
    );
  }
  final directory = Directory(normalized)..createSync(recursive: true);
  final resolved = directory.resolveSymbolicLinksSync();
  if (p.equals(resolved, repositoryRoot) ||
      p.isWithin(repositoryRoot, resolved)) {
    throw const PublicationException(
      "The Firebase receipt directory resolves inside the Git repository.",
      exitCode: 64,
    );
  }
  return Directory(resolved);
}

Future<PreparedReleaseManifest> loadAndValidatePreparedManifest(
  String manifestPath, {
  required String repositoryRoot,
  required Map<String, String> environment,
}) async {
  final manifest = File(manifestPath);
  if (!manifest.existsSync()) {
    throw PublicationException(
      "Prepared manifest does not exist: $manifestPath",
    );
  }
  if (FileSystemEntity.typeSync(manifestPath, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const PublicationException(
      "The prepared manifest must be a regular file, not a symbolic link.",
    );
  }
  final resolvedManifestPath = manifest.resolveSymbolicLinksSync();
  _requireOutsideRepository(resolvedManifestPath, repositoryRoot);
  requireReadOnlyFile(manifest);

  Map<String, dynamic> root;
  try {
    final decoded = jsonDecode(manifest.readAsStringSync());
    root = _requireMap(decoded, "manifest root");
  } on FormatException catch (error) {
    throw PublicationException("Prepared manifest is invalid JSON: $error");
  }

  if (_requireInt(root, "schemaVersion") !=
      preparation.releaseManifestSchemaVersion) {
    throw const PublicationException(
      "Unsupported prepared-manifest schema version.",
    );
  }
  final preparationTool = _requireMap(
    root["preparationTool"],
    "preparationTool",
  );
  if (_requireString(preparationTool, "name") !=
          preparation.preparationToolName ||
      _requireString(preparationTool, "version") !=
          preparation.preparationToolVersion) {
    throw const PublicationException(
      "The manifest was not produced by the pinned preparation tool.",
    );
  }

  final releaseId = _requireString(root, "releaseId");
  if (!RegExp(r"^[A-Za-z0-9][A-Za-z0-9._-]*$").hasMatch(releaseId)) {
    throw const PublicationException("The manifest releaseId is unsafe.");
  }
  if (p.basename(resolvedManifestPath) != "$releaseId.manifest.json") {
    throw const PublicationException(
      "The manifest filename does not match its releaseId.",
    );
  }

  final artifact = _requireMap(root["artifact"], "artifact");
  final apkPath = p.normalize(_requireString(artifact, "absolutePath"));
  final fileName = _requireString(artifact, "fileName");
  final apkSha256 = _requireSha256(artifact, "sha256");
  final apkSizeBytes = _requireInt(artifact, "sizeBytes");
  if (!p.isAbsolute(apkPath) || p.basename(apkPath) != fileName) {
    throw const PublicationException(
      "The manifest APK path must be absolute and match artifact.fileName.",
    );
  }
  if (fileName != "$releaseId.apk") {
    throw const PublicationException(
      "The APK filename does not match the manifest releaseId.",
    );
  }
  final apk = File(apkPath);
  if (!apk.existsSync() ||
      FileSystemEntity.typeSync(apkPath, followLinks: false) !=
          FileSystemEntityType.file) {
    throw PublicationException(
      "The prepared APK is missing or is not a regular file: $apkPath",
    );
  }
  final resolvedApkPath = apk.resolveSymbolicLinksSync();
  _requireOutsideRepository(resolvedApkPath, repositoryRoot);
  requireReadOnlyFile(apk);
  if (apk.lengthSync() != apkSizeBytes) {
    throw const PublicationException(
      "The prepared APK size differs from the manifest.",
    );
  }

  final source = _requireMap(root["source"], "source");
  final commit = _requireString(source, "commit");
  final sourceRemote = _requireString(source, "remote");
  final sourceCommitUrl = _requireString(source, "commitUrl");
  if (!RegExp(r"^[0-9a-f]{40}$").hasMatch(commit) ||
      _requireBool(source, "worktreeClean") != true) {
    throw const PublicationException(
      "The manifest must identify a clean, full Git commit.",
    );
  }
  final expectedSourceUrl =
      "${preparation.normalizeGitHubSourceBaseUrl(sourceRemote)}/commit/$commit";
  if (sourceCommitUrl != expectedSourceUrl) {
    throw const PublicationException(
      "The manifest source URL does not exactly match its remote and commit.",
    );
  }

  final android = _requireMap(root["android"], "android");
  final packageName = _requireString(android, "packageName");
  final versionName = _requireString(android, "versionName");
  final versionCode = _requireInt(android, "versionCode");
  final minSdk = _requireInt(android, "minSdk");
  final targetSdk = _requireInt(android, "targetSdk");
  final compileSdk = _requireInt(android, "compileSdk");
  final abis = _requireStringSet(android, "abis");
  final endpoint = _requireString(android, "compiledDefaultEndpoint");
  final signingCertificate = _requireSha256(
    android,
    "signingCertificateSha256",
  );
  final signatureSchemes = _requireStringBoolMap(android, "signatureSchemes");
  if (packageName != preparation.expectedPackageName ||
      versionName.trim().isEmpty ||
      versionCode <= 0 ||
      _requireString(android, "buildType") != "release" ||
      _requireBool(android, "debuggable") ||
      minSdk != preparation.expectedMinSdk ||
      targetSdk != preparation.expectedTargetSdk ||
      compileSdk != preparation.expectedCompileSdk ||
      !_sameSet(abis, preparation.expectedAbis) ||
      signingCertificate != preparation.expectedSigningCertificateSha256 ||
      signatureSchemes["v2"] != true) {
    throw const PublicationException(
      "The prepared Android metadata does not satisfy the pinned release policy.",
    );
  }
  final canonicalEndpoint = preparation.canonicalizeConfigurableEndpoint(
    endpoint,
  );
  if (canonicalEndpoint != endpoint) {
    throw const PublicationException("The manifest endpoint is not canonical.");
  }

  final tools = preparation.ReleaseToolPaths.fromEnvironment(environment);
  final auditEnvironment = sanitizedPublicationEnvironment(environment);
  final manifestSha256 = await preparation.sha256File(
    resolvedManifestPath,
    shasum: tools.shasum,
    environment: auditEnvironment,
  );
  final actualApkSha256 = await preparation.sha256File(
    resolvedApkPath,
    shasum: tools.shasum,
    environment: auditEnvironment,
  );
  if (actualApkSha256 != apkSha256) {
    throw const PublicationException(
      "The prepared APK SHA-256 differs from the manifest.",
    );
  }

  return PreparedReleaseManifest(
    manifestPath: resolvedManifestPath,
    manifestSha256: manifestSha256,
    releaseId: releaseId,
    apkPath: resolvedApkPath,
    apkSha256: apkSha256,
    apkSizeBytes: apkSizeBytes,
    commit: commit,
    sourceRemote: sourceRemote,
    sourceCommitUrl: sourceCommitUrl,
    packageName: packageName,
    versionName: versionName,
    versionCode: versionCode,
    minSdk: minSdk,
    targetSdk: targetSdk,
    compileSdk: compileSdk,
    abis: Set<String>.unmodifiable(abis),
    compiledDefaultEndpoint: canonicalEndpoint,
    signingCertificateSha256: signingCertificate,
    signatureSchemes: Map<String, bool>.unmodifiable(signatureSchemes),
  );
}

Future<void> reAuditPreparedApk(
  PreparedReleaseManifest prepared, {
  required Map<String, String> environment,
}) async {
  final audit = await preparation.auditAndroidReleaseApk(
    apkPath: prepared.apkPath,
    canonicalEndpoint: prepared.compiledDefaultEndpoint,
    sourceVersion: preparation.ReleaseVersion(
      prepared.versionName,
      prepared.versionCode,
    ),
    tools: preparation.ReleaseToolPaths.fromEnvironment(environment),
    processEnvironment: sanitizedPublicationEnvironment(environment),
  );
  if (audit.packageName != prepared.packageName ||
      audit.version.name != prepared.versionName ||
      audit.version.code != prepared.versionCode ||
      audit.minSdk != prepared.minSdk ||
      audit.targetSdk != prepared.targetSdk ||
      audit.compileSdk != prepared.compileSdk ||
      !_sameSet(audit.abis, prepared.abis) ||
      audit.debuggable ||
      audit.signingCertificateSha256 != prepared.signingCertificateSha256 ||
      audit.sha256 != prepared.apkSha256 ||
      audit.sizeBytes != prepared.apkSizeBytes ||
      !_sameBoolMap(audit.signatureSchemes, prepared.signatureSchemes)) {
    throw const PublicationException(
      "The independent APK audit differs from the prepared manifest.",
    );
  }
}

void requireReadOnlyFile(File file) {
  const writePermissionBits = 0x92; // POSIX 0222.
  if (file.statSync().mode & writePermissionBits != 0) {
    throw PublicationException(
      "Prepared release file is writable: ${file.path}",
    );
  }
}

String readOptionalReleaseNotes(String? path) {
  if (path == null) {
    return "";
  }
  final file = File(path);
  if (!file.existsSync() ||
      FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.file) {
    throw PublicationException("Release-notes file does not exist: $path");
  }
  final value = file.readAsStringSync().trim();
  if (value.contains("\u0000")) {
    throw const PublicationException("Release notes contain a NUL byte.");
  }
  return value;
}

String buildFirebaseReleaseNotes(
  PreparedReleaseManifest prepared, {
  String operatorNotes = "",
}) {
  final sourceBase = prepared.sourceCommitUrl.substring(
    0,
    prepared.sourceCommitUrl.length - "/commit/${prepared.commit}".length,
  );
  final sections = <String>[
    "Ente Photos Self-Hosted ${prepared.versionName} (${prepared.versionCode})",
    "Prepared release: ${prepared.releaseId}\n"
        "APK SHA-256: ${prepared.apkSha256}\n"
        "Source code (AGPL-3.0): ${prepared.sourceCommitUrl}\n"
        "Build instructions: $sourceBase/blob/${prepared.commit}/mobile/apps/photos/SELF_HOSTED_BUILD_GUIDE.md",
    if (operatorNotes.trim().isNotEmpty) operatorNotes.trim(),
  ];
  final notes = "${sections.join("\n\n")}\n";
  if (prepared.sourceCommitUrl.allMatches(notes).length != 1) {
    throw const PublicationException(
      "Release notes must contain the exact source commit URL once.",
    );
  }
  if (utf8.encode(notes).length > _maximumReleaseNotesBytes) {
    throw const PublicationException(
      "Release notes exceed $_maximumReleaseNotesBytes UTF-8 bytes.",
    );
  }
  return notes;
}

Map<String, dynamic> decodeFirebaseCliSuccess(String stdoutValue) {
  Object? decoded;
  try {
    decoded = jsonDecode(stdoutValue);
  } on FormatException catch (error) {
    throw PublicationException("Firebase CLI returned invalid JSON: $error");
  }
  final root = _requireMap(decoded, "Firebase CLI response");
  if (root["status"] != "success") {
    throw const PublicationException("Firebase CLI did not report success.");
  }
  return root;
}

Map<String, dynamic> validateFirebaseAndroidApp(
  Map<String, dynamic> response, {
  required String projectId,
  required String appId,
  required String expectedPackageName,
}) {
  final result = response["result"];
  if (result is! List) {
    throw const PublicationException(
      "Firebase app-list response has no result list.",
    );
  }
  final matches = result
      .map((value) => _requireMap(value, "Firebase Android app"))
      .where((app) => app["appId"] == appId)
      .toList();
  if (matches.length != 1) {
    throw PublicationException(
      "Expected exactly one active Firebase Android app with ID $appId.",
    );
  }
  final app = matches.single;
  if (app["projectId"] != projectId ||
      app["platform"] != "ANDROID" ||
      app["state"] != "ACTIVE" ||
      app["packageName"] != expectedPackageName) {
    throw PublicationException(
      "Firebase app $appId is not the active $expectedPackageName Android "
      "registration in project $projectId.",
    );
  }
  return app;
}

Map<String, dynamic> validateFirebaseGroup(
  Map<String, dynamic> response, {
  required String expectedAlias,
}) {
  final result = _requireMap(response["result"], "Firebase group result");
  final groupsValue = result["groups"];
  if (groupsValue is! List) {
    throw const PublicationException(
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
    throw PublicationException(
      "Expected exactly one Firebase App Distribution group named "
      "'$expectedAlias'.",
    );
  }
  _requireString(matches.single, "displayName");
  return matches.single;
}

FirebaseReleaseReferences parseFirebaseReleaseReferences(String output) {
  final plain = output.replaceAll(RegExp(r"\x1B\[[0-?]*[ -/]*[@-~]"), "");
  String capture(RegExp expression, String label) {
    final match = expression.firstMatch(plain);
    if (match == null) {
      throw PublicationException(
        "Firebase did not return the $label release reference.",
      );
    }
    final uri = Uri.tryParse(match.group(1)!);
    if (uri == null || uri.scheme != "https" || uri.host.isEmpty) {
      throw PublicationException(
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
  return FirebaseReleaseReferences(
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

String confirmationFor(String releaseId) => "PUBLISH $releaseId";

void requireExactConfirmation(String? actual, String expected) {
  if (actual != expected) {
    throw const PublicationException(
      "Publication confirmation did not match; nothing was uploaded.",
      exitCode: 64,
    );
  }
}

Map<String, String> sanitizedPublicationEnvironment(
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
  };
  return Map<String, String>.unmodifiable(
    Map<String, String>.fromEntries(
      environment.entries.where((entry) {
        final key = entry.key.toUpperCase();
        return !exactCredentialKeys.contains(key) &&
            !key.startsWith("SIGNING_") &&
            !key.contains("KEYSTORE_PASSWORD") &&
            !key.contains("KEY_PASSWORD");
      }),
    ),
  );
}

String resolveFirebaseExecutable(Map<String, String> environment) {
  final configured = environment["FIREBASE_CLI"];
  if (configured != null && configured.trim().isNotEmpty) {
    final file = File(configured);
    if (!p.isAbsolute(configured) || !file.existsSync()) {
      throw const PublicationException(
        "FIREBASE_CLI must name an existing absolute executable.",
        exitCode: 69,
      );
    }
    return file.path;
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
  throw const PublicationException(
    "Firebase CLI was not found; set FIREBASE_CLI or add firebase to PATH.",
    exitCode: 69,
  );
}

void validatePublicationVersionLedger(
  String receiptDirectory, {
  required String firebaseAppId,
  required String packageName,
  required int versionCode,
}) {
  int? highestVersionCode;
  String? highestReceipt;
  final receipts = Directory(receiptDirectory)
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith(".firebase-release.json"));
  for (final receipt in receipts) {
    Map<String, dynamic> root;
    try {
      root = _requireMap(
        jsonDecode(receipt.readAsStringSync()),
        "publication receipt",
      );
    } on Object catch (error) {
      throw PublicationException(
        "Cannot validate prior publication receipt ${receipt.path}: $error",
      );
    }
    if (_requireInt(root, "schemaVersion") != publicationReceiptSchemaVersion) {
      throw PublicationException(
        "Unsupported prior publication receipt: ${receipt.path}",
      );
    }
    final firebase = _requireMap(root["firebase"], "firebase");
    final android = _requireMap(root["android"], "android");
    if (firebase["appId"] != firebaseAppId ||
        android["packageName"] != packageName) {
      continue;
    }
    final priorVersion = _requireInt(android, "versionCode");
    if (highestVersionCode == null || priorVersion > highestVersionCode) {
      highestVersionCode = priorVersion;
      highestReceipt = receipt.path;
    }
  }
  if (highestVersionCode != null && versionCode <= highestVersionCode) {
    throw PublicationException(
      "Version code $versionCode is not greater than guarded Firebase release "
      "$highestVersionCode recorded in $highestReceipt.",
    );
  }
}

Map<String, Object?> buildSuccessfulPublicationReceipt({
  required PreparedReleaseManifest prepared,
  required FirebaseRegistration registration,
  required String releaseNotes,
  required FirebaseReleaseReferences references,
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
    "absolutePath": prepared.apkPath,
    "sha256": prepared.apkSha256,
    "sizeBytes": prepared.apkSizeBytes,
  },
  "source": <String, Object?>{
    "commit": prepared.commit,
    "commitUrl": prepared.sourceCommitUrl,
  },
  "android": <String, Object?>{
    "packageName": prepared.packageName,
    "versionName": prepared.versionName,
    "versionCode": prepared.versionCode,
    "compiledDefaultEndpoint": prepared.compiledDefaultEndpoint,
    "signingCertificateSha256": prepared.signingCertificateSha256,
  },
  "firebase": <String, Object?>{
    "projectId": registration.projectId,
    "appId": registration.appId,
    "registeredPackageName": registration.packageName,
    "groupAlias": trustedTesterGroupAlias,
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

String writeFailedPublicationAttempt(
  String receiptDirectory, {
  required PreparedReleaseManifest prepared,
  required FirebaseRegistration registration,
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
    "${prepared.releaseId}.firebase-attempt-$timestamp.json",
  );
  var suffix = 1;
  while (File(attemptPath).existsSync()) {
    attemptPath = p.join(
      receiptDirectory,
      "${prepared.releaseId}.firebase-attempt-$timestamp-$suffix.json",
    );
    suffix++;
  }
  writeImmutableJson(attemptPath, <String, Object?>{
    "schemaVersion": publicationReceiptSchemaVersion,
    "publicationTool": <String, Object?>{
      "name": publicationToolName,
      "version": publicationToolVersion,
    },
    "status": "failed-or-partial",
    "attemptedAt": DateTime.now().toUtc().toIso8601String(),
    "releaseId": prepared.releaseId,
    "artifact": <String, Object?>{
      "absolutePath": prepared.apkPath,
      "sha256": prepared.apkSha256,
    },
    "source": <String, Object?>{
      "commit": prepared.commit,
      "commitUrl": prepared.sourceCommitUrl,
    },
    "android": <String, Object?>{
      "packageName": prepared.packageName,
      "versionName": prepared.versionName,
      "versionCode": prepared.versionCode,
    },
    "firebase": <String, Object?>{
      "projectId": registration.projectId,
      "appId": registration.appId,
      "groupAlias": trustedTesterGroupAlias,
      "exitCode": firebaseExitCode,
      "output": firebaseOutput,
    },
    "releaseNotes": releaseNotes,
    "recovery":
        "Inspect Firebase App Distribution before retrying; an upload may have occurred.",
  });
  return attemptPath;
}

void writeImmutableJson(String finalPath, Map<String, Object?> value) {
  if (File(finalPath).existsSync()) {
    throw PublicationException(
      "Refusing to overwrite existing publication record: $finalPath",
      exitCode: 73,
    );
  }
  final parent = Directory(p.dirname(finalPath));
  if (!parent.existsSync()) {
    throw PublicationException(
      "Publication record directory does not exist: ${parent.path}",
      exitCode: 73,
    );
  }
  final staging = parent.createTempSync(".firebase-receipt-");
  var linked = false;
  try {
    final staged = File(p.join(staging.path, p.basename(finalPath)))
      ..writeAsStringSync(
        "${const JsonEncoder.withIndent("  ").convert(value)}\n",
        flush: true,
      );
    final chmod = Process.runSync("chmod", ["0444", staged.path]);
    if (chmod.exitCode != 0) {
      throw const PublicationException(
        "Could not make the publication record read-only.",
        exitCode: 73,
      );
    }
    final link = Process.runSync("ln", [staged.path, finalPath]);
    if (link.exitCode != 0) {
      throw PublicationException(
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

void requireSamePreparedRelease(
  PreparedReleaseManifest before,
  PreparedReleaseManifest after,
) {
  if (before.manifestSha256 != after.manifestSha256 ||
      before.apkSha256 != after.apkSha256 ||
      before.apkSizeBytes != after.apkSizeBytes ||
      before.releaseId != after.releaseId) {
    throw const PublicationException(
      "The prepared release changed after confirmation; nothing was uploaded.",
    );
  }
}

void printPublicationSummary(
  PreparedReleaseManifest prepared,
  FirebaseRegistration registration, {
  required String receiptDirectory,
  required bool preflightOnly,
}) {
  stdout.writeln();
  stdout.writeln(
    "Guarded Firebase publication ${preflightOnly ? "preflight" : "summary"}:",
  );
  stdout.writeln("  Release: ${prepared.releaseId}");
  stdout.writeln("  APK: ${prepared.apkPath}");
  stdout.writeln("  SHA-256: ${prepared.apkSha256}");
  stdout.writeln(
    "  Android: ${prepared.packageName} ${prepared.versionName} (${prepared.versionCode})",
  );
  stdout.writeln("  Server: ${prepared.compiledDefaultEndpoint}");
  stdout.writeln("  Source: ${prepared.sourceCommitUrl}");
  stdout.writeln("  Firebase project: ${registration.projectId}");
  stdout.writeln("  Firebase app: ${registration.appId}");
  stdout.writeln(
    "  Firebase group: $trustedTesterGroupAlias (${registration.groupDisplayName})",
  );
  stdout.writeln("  Receipt directory: $receiptDirectory");
}

void _requireOutsideRepository(String path, String repositoryRoot) {
  if (p.equals(path, repositoryRoot) || p.isWithin(repositoryRoot, path)) {
    throw const PublicationException(
      "Prepared release files must remain outside the Git repository.",
    );
  }
}

Map<String, dynamic> _requireMap(Object? value, String label) {
  if (value is! Map) {
    throw PublicationException("Expected $label to be a JSON object.");
  }
  try {
    return Map<String, dynamic>.from(value);
  } on Object {
    throw PublicationException("Expected $label to use string JSON keys.");
  }
}

String _requireString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw PublicationException("Expected '$key' to be a non-empty string.");
  }
  return value;
}

String _requireSha256(Map<String, dynamic> map, String key) {
  final value = _requireString(map, key).toLowerCase();
  if (!RegExp(r"^[0-9a-f]{64}$").hasMatch(value)) {
    throw PublicationException("Expected '$key' to be a SHA-256 value.");
  }
  return value;
}

int _requireInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw PublicationException("Expected '$key' to be an integer.");
  }
  return value;
}

bool _requireBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! bool) {
    throw PublicationException("Expected '$key' to be a boolean.");
  }
  return value;
}

Set<String> _requireStringSet(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List || value.any((element) => element is! String)) {
    throw PublicationException("Expected '$key' to be a string list.");
  }
  final result = value.cast<String>().toSet();
  if (result.length != value.length) {
    throw PublicationException("Expected '$key' to contain no duplicates.");
  }
  return result;
}

Map<String, bool> _requireStringBoolMap(Map<String, dynamic> map, String key) {
  final value = _requireMap(map[key], key);
  final result = <String, bool>{};
  for (final entry in value.entries) {
    if (entry.value is! bool) {
      throw PublicationException("Expected '$key' values to be booleans.");
    }
    result[entry.key] = entry.value as bool;
  }
  return result;
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

bool _sameBoolMap(Map<String, bool> left, Map<String, bool> right) =>
    left.length == right.length &&
    left.entries.every((entry) => right[entry.key] == entry.value);

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
