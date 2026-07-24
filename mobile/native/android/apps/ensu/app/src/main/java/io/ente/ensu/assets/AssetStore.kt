package io.ente.ensu.assets

import android.content.Context
import android.os.Environment
import android.util.Log
import io.ente.ensu.bindings.AssetDownloadCallback
import io.ente.ensu.bindings.AssetDownloadProgress
import io.ente.ensu.bindings.Asset
import io.ente.ensu.bindings.AssetStoreCore
import io.ente.ensu.bindings.CancellationToken
import io.ente.ensu.bindings.LegacyAssets
import io.ente.ensu.bindings.KnowledgeReconciliation
import io.ente.ensu.bindings.cleanupObsoleteKnowledgePackRevisions
import io.ente.ensu.bindings.migrateEnsuAssets
import io.ente.ensu.bindings.needsAssetMigration
import io.ente.ensu.bindings.reconcileKnowledgePack
import io.ente.ensu.bindings.uniffiEnsureInitialized
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext

class AssetStore(context: Context) {
    private val appContext = context.applicationContext
    private val assetsDir = File(appContext.noBackupFilesDir, "assets")
    private val legacyLlmDir = appContext.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        ?.let { File(it, "llm") }
    private val legacyTranscriptionDir = File(appContext.dataDir, "app_ensu_transcription_models")
    private val core: AssetStoreCore

    init {
        uniffiEnsureInitialized()
        core = AssetStoreCore(assetsDir.absolutePath)
        AssetDownloadJobService.attach(appContext)
    }

    fun needsMigration(): Boolean = needsAssetMigration(legacyAssets(null, null))

    fun migrate(legacyModelUrl: String?, legacyMmprojUrl: String?): String? {
        File(appContext.filesDir, "llm").deleteRecursively()
        return migrateEnsuAssets(
            assetsDir.absolutePath,
            legacyAssets(legacyModelUrl, legacyMmprojUrl)
        )
    }

    private fun legacyAssets(modelUrl: String?, mmprojUrl: String?) = LegacyAssets(
        llmDir = legacyLlmDir?.absolutePath,
        transcriptionDir = legacyTranscriptionDir.absolutePath,
        modelUrl = modelUrl,
        mmprojUrl = mmprojUrl
    )

    fun assetDir(asset: Asset): File = File(core.assetDir(asset))

    fun llmModelPath(asset: Asset): File? =
        core.llmModelPath(asset)?.let(::File)

    fun llmMmprojPath(asset: Asset): File? =
        core.llmMmprojPath(asset)?.let(::File)

    fun voiceActivityModelPath(asset: Asset): File = File(core.voiceActivityModelPath(asset))

    fun isDownloaded(asset: Asset): Boolean = core.isDownloaded(asset)

    fun removeDownloaded(asset: Asset): Boolean = core.removeDownloaded(asset)

    internal fun reconcileKnowledge(stableId: String): KnowledgeReconciliation =
        reconcileKnowledgePack(core, stableId)

    internal fun cleanupKnowledgeRevisions(stableId: String, activeIdentity: String) =
        cleanupObsoleteKnowledgePackRevisions(core, stableId, activeIdentity)

    suspend fun estimateDownloadSize(asset: Asset): Long? = withContext(Dispatchers.IO) {
        core.estimatedDownloadSize(asset)
    }

    suspend fun download(
        assets: List<Asset>,
        onProgress: (AssetDownloadProgress) -> Unit
    ): Unit = withContext(Dispatchers.IO) {
        if (assets.all { core.isDownloaded(it) }) return@withContext

        val token = CancellationToken()
        val lease = AssetDownloadJobService.begin { token.cancel() }
        try {
            coroutineScope {
                val download = async {
                    core.download(
                        assets,
                        object : AssetDownloadCallback {
                            override fun onProgress(progress: AssetDownloadProgress) {
                                progress.logLine?.let { Log.i("AssetStore", it) }
                                AssetDownloadJobService.update(
                                    lease,
                                    progress.percentage.toInt(),
                                    progress.totalBytes == null
                                )
                                onProgress(progress)
                            }
                        },
                        token
                    )
                }
                try {
                    download.await()
                } catch (e: CancellationException) {
                    token.cancel()
                    throw e
                }
            }
        } finally {
            AssetDownloadJobService.end(lease)
        }
    }
}
