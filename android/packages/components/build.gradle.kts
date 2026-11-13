import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

kotlin { explicitApi() }

android {
    namespace = "io.ente.components"
    compileSdk = 36

    defaultConfig { minSdk = 24 }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }

dependencies {
    implementation(project(":fonts"))

    api("androidx.compose.material3:material3")
    api("androidx.compose.ui:ui")
    api("androidx.compose.ui:ui-text")
    api(platform("androidx.compose:compose-bom:2025.02.00"))
}
