package io.ente.ensu

import android.app.Application
import io.ente.ensu.bindings.RustLogLevel
import io.ente.ensu.bindings.RustLogSink
import io.ente.ensu.bindings.Transcriber
import io.ente.ensu.bindings.initRustLogging
import io.ente.ensu.bindings.transcriptionModelAsset
import io.ente.ensu.bindings.voiceActivityModelAsset
import io.ente.ensu.assets.AssetStore
import io.ente.ensu.knowledge.KnowledgeProvider
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.logging.LogLevel

class EnsuApplication : Application() {
    val logRepository by lazy { FileLogRepository(this) }
    val assetStore by lazy { AssetStore(this) }
    val knowledgeProvider by lazy { KnowledgeProvider(assetStore) }
    val transcriber by lazy {
        val store = assetStore
        val transcription = transcriptionModelAsset()
        val voiceActivity = voiceActivityModelAsset()
        Transcriber(
            store.assetDir(transcription).absolutePath,
            store.voiceActivityModelPath(voiceActivity).absolutePath
        )
    }

    override fun onCreate() {
        super.onCreate()
        initRustLogging(EnsuRustLogSink(logRepository))
    }
}

private class EnsuRustLogSink(
    private val logRepository: FileLogRepository
) : RustLogSink {
    override fun log(level: RustLogLevel, target: String, message: String) {
        val mappedLevel = when (level) {
            RustLogLevel.ERROR -> LogLevel.Error
            RustLogLevel.WARN -> LogLevel.Warning
            RustLogLevel.INFO -> LogLevel.Info
        }
        logRepository.log(mappedLevel, "[$target] $message", tag = "rust")
    }
}
