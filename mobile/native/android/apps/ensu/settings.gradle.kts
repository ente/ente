pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
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
        // gradle/verification-metadata.xml. See mobile/native/onnxruntime/README.md.
        exclusiveContent {
            forRepository {
                ivy {
                    name = "enteOnnxRuntimePackaging"
                    url = uri("https://github.com/laurens-pilot/ort-packaging/releases/download")
                    patternLayout {
                        artifact("ort-[revision]/[artifact]-[revision].[ext]")
                    }
                    metadataSources { artifact() }
                }
            }
            filter { includeGroup("io.ente.onnxruntime") }
        }
    }
}

rootProject.name = "ensu"
include(":app", ":rust")
