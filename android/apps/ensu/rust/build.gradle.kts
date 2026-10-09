import groovy.json.JsonOutput
import groovy.json.JsonSlurper
import java.io.File
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val knownAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")

val debugJniLibsDir = layout.buildDirectory.dir("generated/jniLibs/debug")
val releaseJniLibsDir = layout.buildDirectory.dir("generated/jniLibs/release")

fun capture(vararg cmd: String): String? = runCatching {
    providers.exec { commandLine(*cmd) }.standardOutput.asText.get().trim()
}
    .getOrNull()

fun connectedDeviceAbi(): String? {
    val sdkRoot = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
    val adb = sdkRoot?.let { "$it/platform-tools/adb" } ?: "adb"
    val serial =
        System.getenv("ANDROID_SERIAL")?.takeIf { it.isNotBlank() }
            ?: capture(adb, "devices")
                ?.lines()
                ?.drop(1)
                ?.mapNotNull { l ->
                    l.trim().takeIf { it.endsWith("\tdevice") }?.substringBefore('\t')
                }
                ?.singleOrNull()
            ?: return null
    return capture(adb, "-s", serial, "shell", "getprop", "ro.product.cpu.abi")?.takeIf {
        it in knownAbis
    }
}

fun hostAbi(): String =
    when (System.getProperty("os.arch")) {
        "aarch64",
        "arm64" -> "arm64-v8a"
        "x86_64",
        "amd64" -> "x86_64"
        else -> error("Unsupported host architecture: ${System.getProperty("os.arch")}")
    }

fun ndkToolchain(ndkDir: java.io.File): java.io.File =
    ndkDir.resolve("toolchains/llvm/prebuilt").listFiles { f -> f.isDirectory }?.singleOrNull()
        ?: error("Expected exactly one NDK host toolchain in $ndkDir/toolchains/llvm/prebuilt")

fun packageNativeLibraries(
    messages: File,
    output: File,
    abi: String,
    readElf: (File, String) -> String,
) {
    if (abi == "arm64-v8a") {
        val cpuBackends =
            listOf("armv8.0_1", "armv8.2_1", "armv8.2_2", "armv8.6_1")
                .map { "libggml-cpu-android_$it.so" }
                .toSet()
        val packageId = Regex("""(?:^|[/#])llama-cpp-sys-2(?:@| )0\.1\.158(?:$|[ )])""")
        val parser = JsonSlurper()
        val builds = messages.useLines { lines ->
            lines
                .map {
                    checkNotNull(parser.parseText(it) as? Map<*, *>) { "Invalid Cargo message" }
                }
                .filter {
                    it["reason"] == "build-script-executed" &&
                        packageId.containsMatchIn(it["package_id"].toString())
                }
                .map {
                    val outDir = checkNotNull(it["out_dir"] as? String) { "Missing Cargo out_dir" }
                    File(outDir)
                }
                .toList()
        }
        check(builds.size == 1) { "Expected one llama-cpp-sys-2 build, found $builds" }
        val build = builds.single()
        for (directory in listOf("lib", "lib64", "backends", "build/common")) {
            build
                .resolve(directory)
                .listFiles { file -> file.extension == "so" }
                .orEmpty()
                .filter { !it.name.startsWith("libggml-cpu-") || it.name in cpuBackends }
                .forEach { it.copyTo(output.resolve(it.name), overwrite = true) }
        }
        val required =
            setOf("llama", "mtmd", "ggml", "ggml-base", "llama-common")
                .map { "lib$it.so" }
                .toSet() + cpuBackends
        val missing = required - output.listFiles().orEmpty().map { it.name }.toSet()
        check(missing.isEmpty()) { "Missing native libraries: ${missing.sorted()}" }
    }

    val libraries = output.listFiles { file -> file.extension == "so" }.orEmpty().toList()
    val names = libraries.map { it.name }.toSet()
    val system = setOf("libc.so", "libm.so", "libdl.so", "liblog.so", "libandroid.so", "libz.so")
    val alignment = if (abi in setOf("arm64-v8a", "x86_64")) 16384 else 4096
    for (library in libraries.sortedBy { it.name }) {
        val loads =
            readElf(library, "--program-headers")
                .lineSequence()
                .map { it.trim().split(Regex("\\s+")) }
                .filter { it.first() == "LOAD" }
                .toList()
        check(
            loads.isNotEmpty() && loads.all { it.last().removePrefix("0x").toLong(16) >= alignment }
        ) {
            "${library.name}: PT_LOAD alignment is below ${alignment / 1024} KB"
        }
        val needed =
            Regex("""\(NEEDED\).*?\[(.*?)]""")
                .findAll(readElf(library, "--dynamic"))
                .map { it.groupValues[1] }
                .toSet()
        check(needed.none { "/" in it }) { "${library.name}: absolute DT_NEEDED path" }
        val missing = needed - names - system
        check(missing.isEmpty()) { "${library.name}: unpackaged dependencies ${missing.sorted()}" }
    }
}

fun registerBuildRustJni(
    taskName: String,
    outputDir: Provider<Directory>,
    resolveAbis: () -> List<String>,
) =
    tasks.register<Exec>(taskName) {
        val abis = resolveAbis()

        inputs.files(fileTree(file("../../../../rust")) { exclude("**/target/**") })
        inputs.file(file("scripts/build-rust.sh"))
        inputs.property("abis", abis)
        inputs.property("ndk", providers.provider { android.ndkVersion })
        outputs.dir(outputDir)

        doFirst {
            val version = android.ndkVersion
            val ndkDir = runCatching {
                android.ndkDirectory
            }
                .getOrElse {
                    error("NDK $version is not installed. Run: sdkmanager \"ndk;$version\"")
                }
            val toolchain = ndkToolchain(ndkDir)

            val outDir = outputDir.get().asFile
            outDir.deleteRecursively()
            outDir.mkdirs()

            workingDir = file("scripts")
            commandLine(
                "bash",
                "./build-rust.sh",
                "--toolchain",
                toolchain.absolutePath,
                "--out-dir",
                outDir.absolutePath,
                "--messages-dir",
                temporaryDir.absolutePath,
                *abis.toTypedArray(),
            )
            environment("ANDROID_NDK", ndkDir.absolutePath)
            environment("ANDROID_NDK_ROOT", ndkDir.absolutePath)
            environment("NDK_ROOT", ndkDir.absolutePath)
        }

        doLast {
            val readelf = ndkToolchain(android.ndkDirectory).resolve("bin/llvm-readelf")
            for (abi in abis) {
                packageNativeLibraries(
                    temporaryDir.resolve("$abi.jsonl"),
                    outputDir.get().asFile.resolve(abi),
                    abi,
                ) { library, option ->
                    providers
                        .exec { commandLine(readelf, option, "--wide", library) }
                        .standardOutput
                        .asText
                        .get()
                }
                logger.lifecycle("Packaged and verified native libraries for $abi")
            }
        }
    }

val buildRustJniDebug =
    registerBuildRustJni(
        taskName = "buildRustJniDebug",
        outputDir = debugJniLibsDir,
        resolveAbis = { listOf(connectedDeviceAbi() ?: hostAbi()) },
    )

val buildRustJniRelease =
    registerBuildRustJni(
        taskName = "buildRustJniRelease",
        outputDir = releaseJniLibsDir,
        resolveAbis = { knownAbis },
    )

android {
    namespace = "io.ente.ensu.rust"
    compileSdk = 36
    // Pin the NDK instead of relying on AGP defaults. GitHub-hosted Ubuntu
    // runners already ship 27.3.13750724, so this keeps CI lean while making
    // the requirement explicit for local builds too.
    ndkVersion = "27.3.13750724"

    defaultConfig { minSdk = 24 }

    sourceSets["debug"].jniLibs.setSrcDirs(listOf(debugJniLibsDir))
    sourceSets["release"].jniLibs.setSrcDirs(listOf(releaseJniLibsDir))

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }

tasks.matching { it.name == "preDebugBuild" }.configureEach { dependsOn(buildRustJniDebug) }

tasks.matching { it.name == "preReleaseBuild" }.configureEach { dependsOn(buildRustJniRelease) }

dependencies {
    api("androidx.annotation:annotation:1.7.1")
    // Custom WebGPU/XNNPACK build; the Rust runtime dynamically loads its
    // libonnxruntime.so. Resolved from the Ivy repository declared in
    // settings.gradle.kts and SHA-256 pinned in android/gradle/verification-metadata.xml.
    api("io.ente.onnxruntime:onnxruntime-webgpu-android:1.28.1-r1@aar")
    api("net.java.dev.jna:jna:5.18.1@aar")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0")
}

val checkNativePackaging =
    tasks.register("checkNativePackaging") {
        group = "verification"
        description = "Checks native library selection, dependencies, and page alignment."
        doLast {
            val fixture = temporaryDir.apply {
                deleteRecursively()
                mkdirs()
            }
            fun fixtureFile(path: String, text: String = "test") =
                fixture.resolve(path).apply {
                    parentFile.mkdirs()
                    writeText(text)
                }
            val output = fixture.resolve("jni").apply { mkdirs() }
            val build = fixture.resolve("current")
            val messages =
                fixtureFile(
                    "messages.jsonl",
                    JsonOutput.toJson(
                        mapOf(
                            "reason" to "build-script-executed",
                            "package_id" to
                                "registry+https://github.com/rust-lang/crates.io-index#llama-cpp-sys-2@0.1.158",
                            "out_dir" to build.path,
                        )
                    ),
                )
            var alignment = "0x4000"
            var dependency = "libc.so"
            fun verify(abi: String, expectedError: String? = null) {
                val result = runCatching {
                    packageNativeLibraries(messages, output, abi) { _, option ->
                        if (option == "--program-headers")
                            "  LOAD 0x0 0x0 0x0 0x1000 0x1000 R E $alignment"
                        else " 0x1 (NEEDED) Shared library: [$dependency]"
                    }
                }
                if (expectedError == null) result.getOrThrow()
                else
                    check(result.exceptionOrNull()?.message?.contains(expectedError) == true) {
                        "Expected '$expectedError', got ${result.exceptionOrNull()}"
                    }
            }
            val paths =
                listOf(
                    "lib/libllama.so",
                    "lib/libmtmd.so",
                    "lib/libggml.so",
                    "lib/libggml-base.so",
                    "build/common/libllama-common.so",
                ) +
                    listOf("armv8.0_1", "armv8.2_1", "armv8.2_2", "armv8.6_1").map {
                        "backends/libggml-cpu-android_$it.so"
                    }
            paths.forEach { fixtureFile("current/$it") }
            fixtureFile("current/backends/libggml-cpu-android_armv9.0_1.so")
            fixtureFile("stale.so")
            verify("arm64-v8a")
            check(
                output.listFiles().orEmpty().map { it.name }.toSet() ==
                    paths.map { it.substringAfterLast('/') }.toSet()
            )
            build.resolve("backends/libggml-cpu-android_armv8.0_1.so").delete()
            output.resolve("libggml-cpu-android_armv8.0_1.so").delete()
            verify("arm64-v8a", "Missing native libraries")

            output.deleteRecursively()
            fixtureFile("jni/libc++_shared.so")
            alignment = "0x1000"
            verify("x86_64", "below 16 KB")
            verify("armeabi-v7a")
            alignment = "0x4000"
            dependency = "libggml-base.so"
            verify("x86_64", "unpackaged dependencies")
            logger.lifecycle("Native packaging checks passed (4 cases)")
        }
    }

tasks
    .matching { it.name in listOf("check", "lintDebug") }
    .configureEach { dependsOn(checkNativePackaging) }
