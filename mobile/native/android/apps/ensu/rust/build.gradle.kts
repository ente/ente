import java.io.ByteArrayOutputStream

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val knownAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")

val debugJniLibsDir = layout.buildDirectory.dir("generated/jniLibs/debug")
val releaseJniLibsDir = layout.buildDirectory.dir("generated/jniLibs/release")

fun capture(vararg cmd: String): String? = runCatching {
    val out = ByteArrayOutputStream()
    exec {
        commandLine(*cmd)
        standardOutput = out
        errorOutput = ByteArrayOutputStream()
    }
    out.toString().trim()
}.getOrNull()

fun connectedDeviceAbi(): String? {
    val sdkRoot = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
    val adb = sdkRoot?.let { "$it/platform-tools/adb" } ?: "adb"
    val serial = System.getenv("ANDROID_SERIAL")?.takeIf { it.isNotBlank() }
        ?: capture(adb, "devices")?.lines()?.drop(1)
            ?.mapNotNull { l -> l.trim().takeIf { it.endsWith("\tdevice") }?.substringBefore('\t') }
            ?.singleOrNull()
        ?: return null
    return capture(adb, "-s", serial, "shell", "getprop", "ro.product.cpu.abi")
        ?.takeIf { it in knownAbis }
}

fun hostAbi(): String = when (System.getProperty("os.arch")) {
    "aarch64", "arm64" -> "arm64-v8a"
    "x86_64", "amd64" -> "x86_64"
    else -> error("Unsupported host architecture: ${System.getProperty("os.arch")}")
}

fun ndkToolchain(ndkDir: java.io.File): java.io.File =
    ndkDir.resolve("toolchains/llvm/prebuilt")
        .listFiles { f -> f.isDirectory }
        ?.singleOrNull()
        ?: error("Expected exactly one NDK host toolchain in $ndkDir/toolchains/llvm/prebuilt")

fun registerBuildRustJni(
    taskName: String,
    outputDir: Provider<Directory>,
    resolveAbis: () -> List<String>,
) = tasks.register(taskName) {
    val abis = resolveAbis()

    inputs.files(fileTree(file("../../../../../../rust")) { exclude("**/target/**") })
    inputs.file(file("scripts/build-rust.sh"))
    inputs.property("abis", abis)
    inputs.property("ndk", providers.provider { android.ndkVersion })
    outputs.dir(outputDir)

    doLast {
        val version = android.ndkVersion
        val ndkDir = runCatching { android.ndkDirectory }.getOrElse {
            error("NDK $version is not installed. Run: sdkmanager \"ndk;$version\"")
        }
        val toolchain = ndkToolchain(ndkDir)

        val outDir = outputDir.get().asFile
        outDir.deleteRecursively()
        outDir.mkdirs()

        exec {
            workingDir = file("scripts")
            commandLine(
                "bash",
                "./build-rust.sh",
                "--toolchain", toolchain.absolutePath,
                "--out-dir", outDir.absolutePath,
                *abis.toTypedArray(),
            )
            environment("ANDROID_NDK", ndkDir.absolutePath)
            environment("ANDROID_NDK_ROOT", ndkDir.absolutePath)
            environment("NDK_ROOT", ndkDir.absolutePath)
        }
    }
}

val buildRustJniDebug = registerBuildRustJni(
    taskName = "buildRustJniDebug",
    outputDir = debugJniLibsDir,
    resolveAbis = { listOf(connectedDeviceAbi() ?: hostAbi()) },
)

val buildRustJniRelease = registerBuildRustJni(
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

    defaultConfig {
        minSdk = 24
    }

    sourceSets["debug"].jniLibs.setSrcDirs(listOf(debugJniLibsDir))
    sourceSets["release"].jniLibs.setSrcDirs(listOf(releaseJniLibsDir))

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

tasks.matching { it.name == "preDebugBuild" }.configureEach {
    dependsOn(buildRustJniDebug)
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(buildRustJniRelease)
}

dependencies {
    api("net.java.dev.jna:jna:5.18.1@aar")
    api("androidx.annotation:annotation:1.7.1")
    // Custom WebGPU/XNNPACK build; the Rust runtime dynamically loads its
    // libonnxruntime.so. Resolved from the Ivy repository declared in
    // settings.gradle.kts and SHA-256 pinned in gradle/verification-metadata.xml.
    api("io.ente.onnxruntime:onnxruntime-webgpu-android:1.27.0-r2@aar")
}
