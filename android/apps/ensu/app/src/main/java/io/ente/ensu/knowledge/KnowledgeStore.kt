package io.ente.ensu.knowledge

import android.content.Context
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import io.ente.ensu.AppState
import io.ente.ensu.bindings.AssetDownloadException
import io.ente.ensu.bindings.KnowledgeDatasetConfig
import io.ente.ensu.bindings.KnowledgeReconciliation
import io.ente.ensu.bindings.KnowledgeReconciliationStatus
import io.ente.ensu.coroutines.runCatchingCancellable
import io.ente.ensu.device.isChatSupported
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.logging.LogLevel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

private val Context.legacyKnowledgePreferences by preferencesDataStore("ensu_knowledge_preferences")

data class KnowledgePackState(
    val config: KnowledgeDatasetConfig,
    val status: KnowledgeReconciliationStatus? = null,
    val activeIdentity: String? = null,
    val inventoryLoaded: Boolean = false,
    val mutationProgress: KnowledgeDownloadProgress? = null,
    val errorMessage: String? = null,
) {
    val isMutating: Boolean
        get() = mutationProgress != null
}

data class KnowledgeState(
    val packs: Map<String, KnowledgePackState> = emptyMap(),
    val disabledIds: Set<String> = emptySet(),
    val inventoryLoading: Boolean = true,
    val settingsReady: Boolean = false,
) {
    val inventoryReady: Boolean
        get() = settingsReady && !inventoryLoading && packs.values.all { it.inventoryLoaded }

    val readyDatasets: List<KnowledgeDatasetConfig>
        get() =
            packs.values
                .filter { pack ->
                    pack.status == KnowledgeReconciliationStatus.READY ||
                        pack.status == KnowledgeReconciliationStatus.UPDATE_AVAILABLE
                }
                .map { it.config }
}

class KnowledgeStore(
    context: Context,
    private val state: MutableStateFlow<AppState>,
    private val provider: KnowledgeProvider,
    datasets: List<KnowledgeDatasetConfig>,
    private val logRepository: FileLogRepository,
) {
    private val preferences = KnowledgePreferences(context)
    private val catalog = datasets.associateBy { it.stableId }
    private val jobs = mutableMapOf<String, Job>()
    private var scope: CoroutineScope? = null
    private var bootstrapJob: Job? = null
    private val packsReady = CompletableDeferred<Unit>()

    fun bootstrap(scope: CoroutineScope, retryFailed: Boolean = false) {
        this.scope = scope
        if (bootstrapJob?.isActive == true || (bootstrapJob != null && !retryFailed)) return
        if (state.value.knowledge.inventoryReady) return
        if (bootstrapJob == null)
            state.update { appState ->
                appState.copy(
                    knowledge =
                        appState.knowledge.copy(
                            packs = catalog.mapValues { (_, config) -> KnowledgePackState(config) }
                        )
                )
            }
        state.update { it.copy(knowledge = it.knowledge.copy(inventoryLoading = true)) }
        bootstrapJob = scope.launch {
            try {
                preferences.migratePackSettings(catalog.keys)
                val disabledIds = preferences.disabledPackIds
                state.update {
                    it.copy(
                        knowledge =
                            it.knowledge.copy(
                                disabledIds = disabledIds,
                                settingsReady = true,
                            )
                    )
                }
                catalog.values
                    .filter { state.value.knowledge.packs[it.stableId]?.inventoryLoaded != true }
                    .forEach { dataset -> reconcileAndUpdate(dataset) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                logRepository.log(
                    LogLevel.Error,
                    "Could not load source preferences",
                    tag = "Knowledge",
                    throwable = error,
                )
            } finally {
                state.update { it.copy(knowledge = it.knowledge.copy(inventoryLoading = false)) }
                packsReady.complete(Unit)
            }
        }
    }

    suspend fun awaitReady() {
        packsReady.await()
        bootstrapJob?.join()
    }

    fun retry() {
        scope?.let { bootstrap(it, retryFailed = true) }
    }

    fun setEnabled(stableId: String, enabled: Boolean) {
        preferences.setPackEnabled(stableId, enabled)
        state.update {
            it.copy(knowledge = it.knowledge.copy(disabledIds = preferences.disabledPackIds))
        }
    }

    fun downloadOrUpdate(stableId: String) {
        if (!state.value.chat.deviceCapability.isChatSupported()) return
        val dataset = catalog[stableId] ?: return
        val ownerScope = scope ?: return
        if (jobs[stableId]?.isActive == true) return
        val wasInstalled = state.value.knowledge.packs[stableId]?.activeIdentity != null
        updatePack(stableId) {
            it.copy(
                mutationProgress = KnowledgeDownloadProgress("Starting download...", 0.0),
                errorMessage = null,
            )
        }
        jobs[stableId] = ownerScope.launch {
            try {
                val reconciliation =
                    provider.download(dataset) { progress ->
                        updatePack(stableId) { current ->
                            current.copy(mutationProgress = progress)
                        }
                    }
                updatePack(stableId) {
                    it.fromReconciliation(reconciliation).copy(mutationProgress = null)
                }
                if (!wasInstalled && reconciliation.activeIdentity != null)
                    setEnabled(stableId, true)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                val reconciled = runCatchingCancellable { provider.reconcile(dataset) }.getOrNull()
                updatePack(stableId) { current ->
                    (reconciled?.let { current.fromReconciliation(it) } ?: current).copy(
                        mutationProgress = null,
                        errorMessage = userFacingKnowledgeError(error),
                    )
                }
                logRepository.log(
                    LogLevel.Error,
                    "Knowledge pack setup failed",
                    details = "pack=$stableId error=${error.message}",
                    tag = "Knowledge",
                )
            } finally {
                jobs.remove(stableId)
            }
        }
    }

    fun cancel(stableId: String) {
        val dataset = catalog[stableId] ?: return
        val ownerScope = scope ?: return
        val ownerJob = jobs[stableId]
        ownerScope.launch {
            val result = runCatchingCancellable { provider.cancel(dataset) }.getOrNull()
            ownerJob?.join()
            if (jobs[stableId]?.isActive == true) return@launch
            updatePack(stableId) { current ->
                (result?.let { current.fromReconciliation(it) } ?: current).copy(
                    mutationProgress = null
                )
            }
        }
    }

    private fun updatePack(
        stableId: String,
        transform: (KnowledgePackState) -> KnowledgePackState,
    ) {
        state.update { appState ->
            val current = appState.knowledge.packs[stableId] ?: return@update appState
            appState.copy(
                knowledge =
                    appState.knowledge.copy(
                        packs = appState.knowledge.packs + (stableId to transform(current))
                    )
            )
        }
    }

    private suspend fun reconcileAndUpdate(dataset: KnowledgeDatasetConfig) {
        val result = runCatchingCancellable { provider.reconcile(dataset) }
        updatePack(dataset.stableId) { current ->
            result.fold(
                onSuccess = { reconciliation -> current.fromReconciliation(reconciliation) },
                onFailure = { error ->
                    current.copy(
                        status = KnowledgeReconciliationStatus.DOWNLOAD,
                        errorMessage = userFacingKnowledgeError(error),
                    )
                },
            )
        }
    }

    private fun KnowledgePackState.fromReconciliation(
        result: KnowledgeReconciliation
    ): KnowledgePackState =
        copy(
            status = result.status,
            activeIdentity = result.activeIdentity,
            inventoryLoaded = true,
            errorMessage = null,
        )

    private fun userFacingKnowledgeError(error: Throwable): String {
        return when (error) {
            is AssetDownloadException.Cancelled -> "Download cancelled"
            is AssetDownloadException.StorageFull ->
                "Not enough storage space to download this knowledge pack."
            is AssetDownloadException.Network ->
                "Couldn't download the knowledge pack. Check your connection and try again."
            is AssetDownloadException.Http ->
                "The knowledge pack is currently unavailable. Please try again later."
            is AssetDownloadException.Validation,
            is AssetDownloadException.InvalidDownload ->
                "The knowledge pack couldn't be verified. Please try again."
            is AssetDownloadException.Io -> "Couldn't save the knowledge pack. Please try again."
            else -> "Knowledge pack setup failed. Please try again."
        }
    }
}

private class KnowledgePreferences(context: Context) {
    private val legacyPreferences = context.applicationContext.legacyKnowledgePreferences
    private val preferences =
        context.applicationContext.getSharedPreferences("ensu_chat_sources", Context.MODE_PRIVATE)

    val disabledPackIds: Set<String>
        get() = preferences.getStringSet("disabled_pack_defaults", emptySet()).orEmpty().toSet()

    suspend fun migratePackSettings(packIds: Set<String>) {
        if (preferences.getBoolean("pack_defaults_migrated", false)) return
        val legacy = legacyPreferences.data.first()[stringSetPreferencesKey("enabled_dataset_ids")]
        val editor = preferences.edit()
        if (!preferences.contains("disabled_pack_defaults")) {
            editor.putStringSet("disabled_pack_defaults", legacy?.let { packIds - it }.orEmpty())
        }
        editor.putBoolean("pack_defaults_migrated", true).apply()
    }

    fun setPackEnabled(id: String, enabled: Boolean) {
        val ids = disabledPackIds.let { if (enabled) it - id else it + id }
        preferences.edit().putStringSet("disabled_pack_defaults", ids).apply()
    }
}
