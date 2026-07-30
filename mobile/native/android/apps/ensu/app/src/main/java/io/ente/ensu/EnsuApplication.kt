package io.ente.ensu

import android.app.Application
import io.ente.ensu.bindings.Transcriber
import io.ente.ensu.bindings.transcriptionModelAsset
import io.ente.ensu.bindings.voiceActivityModelAsset
import io.ente.ensu.assets.AssetStore
import io.ente.ensu.knowledge.KnowledgeProvider

class EnsuApplication : Application() {
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
}
