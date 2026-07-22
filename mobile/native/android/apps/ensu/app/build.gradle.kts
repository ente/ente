import java.io.ByteArrayOutputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
}

configurations.configureEach {
    exclude(group = "com.google.guava", module = "listenablefuture")
}

val keystorePropsFile = rootProject.file("key.properties")
val keystoreProps = Properties()
val hasReleaseKeystore = keystorePropsFile.exists()
if (hasReleaseKeystore) {
    keystorePropsFile.inputStream().use { keystoreProps.load(it) }
}

val knownAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")

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
            ?.mapNotNull { line ->
                line.trim().takeIf { it.endsWith("\tdevice") }?.substringBefore('\t')
            }
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

val debugAbis = listOf(connectedDeviceAbi() ?: hostAbi())

android {
    namespace = "io.ente.ensu"
    compileSdk = 36

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                storeFile = file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
            } else {
                storeFile = file("../debug.keystore")
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }

    defaultConfig {
        applicationId = "io.ente.ensu"
        minSdk = 24
        targetSdk = 36
        versionCode = (project.findProperty("versionCode") as? String)?.toInt() ?: 33
        versionName = "0.1.18"
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            ndk {
                abiFilters += debugAbis
            }
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            ndk {
                abiFilters += knownAbis
            }
        }
    }

    buildFeatures {
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.11"
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
        jniLibs {
            pickFirsts += setOf(
                "lib/arm64-v8a/libc++_shared.so",
                "lib/armeabi-v7a/libc++_shared.so",
                "lib/x86/libc++_shared.so",
                "lib/x86_64/libc++_shared.so"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.02.02")

    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.activity:activity-compose:1.8.2")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.animation:animation")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-text")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")
    implementation("androidx.navigation:navigation-compose:2.7.7")
    implementation("com.google.accompanist:accompanist-navigation-animation:0.34.0")
    implementation(project(":rust"))

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0")
    implementation("androidx.datastore:datastore-preferences:1.1.1")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")

    implementation("com.github.gregcockroft:AndroidMath:v1.1.0") {
        exclude(group = "com.google.guava", module = "listenablefuture")
    }

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
