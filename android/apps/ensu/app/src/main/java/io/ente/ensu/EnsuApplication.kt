package io.ente.ensu

import android.app.Application
import android.content.ComponentCallbacks2
import android.os.Build
import io.ente.ensu.assets.AssetStore
import io.ente.ensu.bindings.RustLogLevel
import io.ente.ensu.bindings.RustLogSink
import io.ente.ensu.bindings.Transcriber
import io.ente.ensu.bindings.initRustLogging
import io.ente.ensu.bindings.transcriptionModelAsset
import io.ente.ensu.knowledge.KnowledgeProvider
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.logging.LogLevel
import io.ente.ensu.notifications.BackgroundGeneration
import io.ente.ensu.notifications.NotificationPermissions

class EnsuApplication : Application() {
    val backgroundGeneration by lazy { BackgroundGeneration(this) }
    val notificationPermissions by lazy { NotificationPermissions(this) }
    private val runtimeDelegate = lazy { AppRuntime(this) }
    val runtime by runtimeDelegate
    val logRepository by lazy { FileLogRepository(this) }
    val assetStore by lazy { AssetStore(this) }
    val knowledgeProvider by lazy { KnowledgeProvider(assetStore) }
    val transcriber by lazy {
        val store = assetStore
        val transcription = transcriptionModelAsset()
        Transcriber.withCache(
            store.assetDir(transcription).absolutePath,
            store.voiceActivityModelPath().absolutePath,
            cacheDir.absolutePath,
            "${Build.FINGERPRINT}|${Build.HARDWARE}|${Build.SUPPORTED_ABIS.joinToString()}",
        )
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level != ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN && runtimeDelegate.isInitialized()) {
            runtime.store.handleMemoryPressure()
        }
    }

    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(backgroundGeneration)
        initRustLogging(EnsuRustLogSink(logRepository))
    }
}

private class EnsuRustLogSink(private val logRepository: FileLogRepository) : RustLogSink {
    override fun log(level: RustLogLevel, target: String, message: String) {
        val mappedLevel =
            when (level) {
                RustLogLevel.ERROR -> LogLevel.Error
                RustLogLevel.WARN -> LogLevel.Warning
                RustLogLevel.INFO -> LogLevel.Info
            }
        logRepository.log(mappedLevel, "[$target] $message", tag = "rust")
    }
}
