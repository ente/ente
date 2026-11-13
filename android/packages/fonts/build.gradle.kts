import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

kotlin { explicitApi() }

android {
    namespace = "io.ente.fonts"
    compileSdk = 36

    defaultConfig { minSdk = 24 }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }

dependencies {
    api("androidx.compose.ui:ui-text")
    api(platform("androidx.compose:compose-bom:2025.02.00"))
}
