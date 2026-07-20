package io.ente.ensu.llm

import android.content.Context
import android.os.Environment
import android.util.Log
import io.ente.ensu.bindings.ModelDownloadCallback
import io.ente.ensu.bindings.ModelDownloadCore
import io.ente.ensu.bindings.ModelDownloadProgress
import io.ente.ensu.bindings.LlmException
import io.ente.ensu.bindings.ModelDownloadTarget
import io.ente.ensu.bindings.migrateEnsuLegacyModels
import io.ente.ensu.bindings.uniffiEnsureInitialized
import io.ente.ensu.config.loadConfigDefaults
import java.io.File
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext

class ModelDownloader(context: Context) {
    private val appContext = context.applicationContext
    private val modelsDir = File(appContext.noBackupFilesDir, "models")
    private val legacyDir = appContext.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        ?.let { File(it, "llm") }
    private val legacyTranscriptionDir = File(appContext.dataDir, "app_ensu_transcription_models")
    private val downloadMutex = Mutex()
    private val core: ModelDownloadCore
    val transcriptionModelTarget: ModelDownloadTarget
    val voiceActivityModelTarget: ModelDownloadTarget

    init {
        uniffiEnsureInitialized()
        ModelDownloadJobService.attach(appContext)
        core = ModelDownloadCore(modelsDir.absolutePath)
        val defaults = loadConfigDefaults()
        transcriptionModelTarget = ModelDownloadTarget.TarGz(
            defaults.transcriptionModel.id,
            defaults.transcriptionModel.url
        )
        voiceActivityModelTarget = ModelDownloadTarget.Onnx(
            defaults.voiceActivityModel.id,
            defaults.voiceActivityModel.url
        )
    }

    fun needsMigration(): Boolean =
        legacyDir?.exists() == true || legacyTranscriptionDir.exists()

    fun migrate(targets: List<ModelDownloadTarget>) {
        File(appContext.filesDir, "llm").deleteRecursively()
        migrateEnsuLegacyModels(
            modelsDir.absolutePath,
            legacyDir?.absolutePath,
            legacyTranscriptionDir.absolutePath,
            targets,
            transcriptionModelTarget,
            voiceActivityModelTarget
        )
    }

    val isDownloadActive: Boolean get() = core.isDownloadActive()

    fun modelPath(target: ModelDownloadTarget): File = File(core.modelPath(target))

    fun mmprojPath(target: ModelDownloadTarget): String? = core.mmprojPath(target)

    fun isDownloaded(target: ModelDownloadTarget): Boolean = core.isDownloaded(target)

    fun removeDownloaded(target: ModelDownloadTarget): Boolean = core.removeDownloaded(target)

    fun cancel() = core.cancel()

    suspend fun estimateDownloadSize(target: ModelDownloadTarget): Long? = withContext(Dispatchers.IO) {
        core.estimatedDownloadSize(target)
    }

    suspend fun download(
        targets: List<ModelDownloadTarget>,
        onProgress: (DownloadProgress) -> Unit
    ): Boolean = withContext(Dispatchers.IO) {
        if (!downloadMutex.tryLock()) throw LlmException.Cancelled()
        try {
            downloadLocked(targets, onProgress)
        } finally {
            downloadMutex.unlock()
        }
    }

    private suspend fun downloadLocked(
        targets: List<ModelDownloadTarget>,
        onProgress: (DownloadProgress) -> Unit
    ): Boolean {
        val downloadJob = coroutineContext[Job]
        if (targets.all { core.isDownloaded(it) }) return false

        ModelDownloadJobService.begin { core.cancel() }
        return try {
            core.download(
                targets,
                object : ModelDownloadCallback {
                    override fun onProgress(progress: ModelDownloadProgress) {
                        progress.logLine?.let { Log.i("ModelDownloader", it) }
                        ModelDownloadJobService.update(progress.percent, progress.totalBytes == null)
                        onProgress(DownloadProgress(progress.percent, progress.status))
                    }

                    override fun isCancelled(): Boolean = downloadJob?.isCancelled == true
                }
            )
        } finally {
            ModelDownloadJobService.end()
        }
    }
}
