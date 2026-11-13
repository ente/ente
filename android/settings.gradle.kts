pluginManagement {
    repositories {
        google()
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
        // Ente's custom prebuilt ONNX Runtime AAR is resolved straight from
        // its GitHub release; its SHA-256 is pinned in
        // android/gradle/verification-metadata.xml.
        exclusiveContent {
            forRepository {
                ivy {
                    name = "enteOnnxRuntimePackaging"
                    url = uri("https://github.com/ente/ort-packaging/releases/download")
                    patternLayout { artifact("ort-[revision]/[artifact]-[revision].[ext]") }
                    metadataSources { artifact() }
                }
            }
            filter { includeGroup("io.ente.onnxruntime") }
        }
    }
}

rootProject.name = "android"

include(":components")

project(":components").projectDir = file("packages/components")

include(":ensu")

project(":ensu").projectDir = file("apps/ensu")

include(":ensu:app", ":ensu:rust")

include(":fonts")

project(":fonts").projectDir = file("packages/fonts")
