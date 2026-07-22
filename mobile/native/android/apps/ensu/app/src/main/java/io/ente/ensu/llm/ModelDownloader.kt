package io.ente.ensu.llm

import android.content.Context
import android.os.Environment
import android.util.Log
import io.ente.ensu.bindings.CancellationToken
import io.ente.ensu.bindings.ModelDownloadCallback
import io.ente.ensu.bindings.ModelDownloadCore
import io.ente.ensu.bindings.ModelDownloadProgress
import io.ente.ensu.bindings.LlmException
import io.ente.ensu.bindings.ModelTarget
import io.ente.ensu.bindings.LegacyModels
import io.ente.ensu.bindings.migrateMobileModels
import io.ente.ensu.bindings.transcriptionModelTarget
import io.ente.ensu.bindings.voiceActivityModelTarget
import io.ente.ensu.bindings.uniffiEnsureInitialized
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
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
    val transcriptionTarget: ModelTarget
    val voiceActivityTarget: ModelTarget

    init {
        uniffiEnsureInitialized()
        ModelDownloadJobService.attach(appContext)
        core = ModelDownloadCore(modelsDir.absolutePath)
        transcriptionTarget = transcriptionModelTarget()
        voiceActivityTarget = voiceActivityModelTarget()
    }

    fun needsMigration(): Boolean =
        legacyDir?.exists() == true || legacyTranscriptionDir.exists()

    fun migrate(legacyModelUrl: String?, legacyMmprojUrl: String?): String? {
        File(appContext.filesDir, "llm").deleteRecursively()
        return migrateMobileModels(
            modelsDir.absolutePath,
            LegacyModels(
                legacyDir?.absolutePath,
                legacyTranscriptionDir.absolutePath,
                legacyModelUrl,
                legacyMmprojUrl
            )
        )
    }

    val isDownloadActive: Boolean get() = core.isDownloadActive()

    fun modelDir(target: ModelTarget): File = File(core.modelDir(target))

    fun llmModelPath(target: ModelTarget): File? =
        core.llmModelPath(target)?.let(::File)

    fun llmMmprojPath(target: ModelTarget): File? =
        core.llmMmprojPath(target)?.let(::File)

    fun voiceActivityModelPath(): File = File(core.voiceActivityModelPath())

    fun isDownloaded(target: ModelTarget): Boolean = core.isDownloaded(target)

    fun removeDownloaded(target: ModelTarget): Boolean = core.removeDownloaded(target)

    suspend fun estimateDownloadSize(target: ModelTarget): Long? = withContext(Dispatchers.IO) {
        core.estimatedDownloadSize(target)
    }

    suspend fun download(
        targets: List<ModelTarget>,
        onProgress: (DownloadProgress) -> Unit
    ): Unit = withContext(Dispatchers.IO) {
        if (!downloadMutex.tryLock()) throw LlmException.Cancelled()
        try {
            downloadLocked(targets, onProgress)
        } finally {
            downloadMutex.unlock()
        }
    }

    private suspend fun downloadLocked(
        targets: List<ModelTarget>,
        onProgress: (DownloadProgress) -> Unit
    ) {
        if (targets.all { core.isDownloaded(it) }) return

        val token = CancellationToken()
        ModelDownloadJobService.begin { token.cancel() }
        try {
            coroutineScope {
                val download = async {
                    core.download(
                        targets,
                        object : ModelDownloadCallback {
                            override fun onProgress(progress: ModelDownloadProgress) {
                                progress.logLine?.let { Log.i("ModelDownloader", it) }
                                ModelDownloadJobService.update(progress.percent, progress.totalBytes == null)
                                onProgress(DownloadProgress(progress.percent, progress.status))
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
            ModelDownloadJobService.end()
        }
    }
}
