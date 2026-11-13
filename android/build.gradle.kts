import com.android.build.api.dsl.CommonExtension
import com.ncorti.ktfmt.gradle.KtfmtExtension
import com.ncorti.ktfmt.gradle.tasks.KtfmtBaseTask
import dev.detekt.gradle.Detekt
import dev.detekt.gradle.extensions.DetektExtension
import org.jetbrains.kotlin.gradle.tasks.KotlinCompilationTask

plugins {
    id("com.android.application") version "8.12.2" apply false
    id("com.android.library") version "8.12.2" apply false
    id("com.ncorti.ktfmt.gradle") version "0.27.0"
    id("dev.detekt") version "2.0.0-alpha.6"
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
    id("org.jetbrains.kotlin.jvm") version "2.4.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.20" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.4.20" apply false
}

allprojects {
    apply(plugin = "com.ncorti.ktfmt.gradle")
    apply(plugin = "dev.detekt")
    extensions.configure<KtfmtExtension> { kotlinLangStyle() }

    extensions.configure<DetektExtension> {
        buildUponDefaultConfig.set(true)
        config.setFrom(rootProject.file("detekt.yml"))
        ignoredBuildTypes.set(listOf("release"))
    }

    tasks.withType<KtfmtBaseTask>().configureEach { exclude("**/io/ente/ensu/bindings/ensu.kt") }
    tasks.withType<Detekt>().configureEach { exclude("**/io/ente/ensu/bindings/ensu.kt") }

    listOf("com.android.application", "com.android.library").forEach { id ->
        pluginManager.withPlugin(id) {
            extensions.configure<CommonExtension<*, *, *, *, *, *>>("android") {
                lint {
                    warningsAsErrors = true
                    disable +=
                        setOf(
                            "ChromeOsAbiSupport",
                            "GradleDependency",
                            "IconLauncherShape",
                            "OldTargetApi",
                            "UseKtx",
                            "VectorPath",
                        )
                    checkTestSources = true
                    checkDependencies = true
                }
            }
        }
    }

    tasks.withType<KotlinCompilationTask<*>>().configureEach {
        compilerOptions.allWarningsAsErrors.set(true)
    }
}

tasks.register("lint") {
    dependsOn(
        allprojects.map { project ->
            project.tasks.matching {
                it.name in listOf("ktfmtCheck", "detekt", "detektMain", "detektTest", "lintDebug")
            }
        }
    )
}
