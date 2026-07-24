package io.ente.ensu

import android.app.Application
import io.ente.ensu.bindings.Transcriber
import io.ente.ensu.knowledge.KnowledgeProvider
import io.ente.ensu.llm.ModelDownloader

class EnsuApplication : Application() {
    val modelDownloader by lazy { ModelDownloader(this) }
    val knowledgeProvider by lazy { KnowledgeProvider(noBackupFilesDir.resolve("knowledge")) }
    val transcriber by lazy {
        Transcriber(
            modelDownloader.modelDir(modelDownloader.transcriptionTarget).absolutePath,
            modelDownloader.voiceActivityModelPath().absolutePath
        )
    }
}
