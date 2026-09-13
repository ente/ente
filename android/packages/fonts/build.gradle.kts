import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("com.ncorti.ktfmt.gradle")
    id("org.jetbrains.kotlin.android")
}

kotlin { explicitApi() }

ktfmt {
    kotlinLangStyle()
    maxWidth.set(100)
}

android {
    namespace = "io.ente.fonts"
    compileSdk = 36

    defaultConfig { minSdk = 26 }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        abortOnError = true
        warningsAsErrors = true
        disable += setOf("AndroidGradlePluginVersion", "GradleDependency")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
        allWarningsAsErrors = true
    }
}

dependencies {
    val composeBom = platform(libs.androidx.compose.bom)

    api(composeBom)
    api("androidx.compose.ui:ui-text")
}
