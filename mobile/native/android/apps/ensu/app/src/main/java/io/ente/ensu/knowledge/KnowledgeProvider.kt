package io.ente.ensu.knowledge

import io.ente.ensu.assets.AssetStore
import io.ente.ensu.bindings.KnowledgeDatasetConfig
import io.ente.ensu.bindings.KnowledgePromptHit
import io.ente.ensu.bindings.KnowledgeReconciliation
import io.ente.ensu.bindings.RetrievalIndex
import io.ente.ensu.bindings.knowledgePackAsset
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class KnowledgeProvider(
    private val assetStore: AssetStore
) {
    private data class ActiveMutation(
        val task: Deferred<KnowledgeReconciliation>
    )

    private data class OpenIndex(
        val directory: String,
        val index: RetrievalIndex
    )

    private val mutationGate = Mutex()
    private val mutations = mutableMapOf<String, ActiveMutation>()
    private val lifecycleGates = mutableMapOf<String, Mutex>()
    private val indexGate = Mutex()
    private val indexes = mutableMapOf<String, OpenIndex>()

    suspend fun reconcile(dataset: KnowledgeDatasetConfig): KnowledgeReconciliation =
        lifecycleGate(dataset.stableId).withLock {
            val activeMutation = mutationGate.withLock { mutations[dataset.stableId] }
            if (activeMutation != null) {
                val result = runCatching { activeMutation.task.await() }
                mutationGate.withLock {
                    if (
                        mutations[dataset.stableId] === activeMutation &&
                        activeMutation.task.isCompleted
                    ) {
                        mutations.remove(dataset.stableId)
                    }
                }
                result.getOrNull()?.let { return@withLock it }
                currentCoroutineContext().ensureActive()
            }
            withContext(Dispatchers.IO) {
                indexGate.withLock {
                    reconcileAndOpenLocked(dataset)
                }
            }
        }

    suspend fun download(
        dataset: KnowledgeDatasetConfig,
        onProgress: (KnowledgeDownloadProgress) -> Unit
    ): KnowledgeReconciliation = coroutineScope {
        var ownsMutation = false
        val mutation = lifecycleGate(dataset.stableId).withLock {
            mutationGate.withLock {
                mutations[dataset.stableId] ?: run {
                    ownsMutation = true
                    val task = async(Dispatchers.IO) {
                        try {
                            assetStore.download(listOf(knowledgePackAsset(dataset.stableId))) {
                                onProgress(KnowledgeDownloadProgress(it.label, it.percentage))
                            }
                            indexGate.withLock {
                                val result = reconcileAndOpenLocked(dataset)
                                check(result.activeIdentity == dataset.currentDownloadIdentity) {
                                    "Downloaded knowledge pack failed current revision validation"
                                }
                                result
                            }
                        } catch (error: Throwable) {
                            withContext(NonCancellable) {
                                indexGate.withLock {
                                    runCatching { reconcileAndOpenLocked(dataset) }
                                }
                            }
                            throw error
                        }
                    }
                    ActiveMutation(task).also {
                        mutations[dataset.stableId] = it
                    }
                }
            }
        }

        try {
            mutation.task.await()
        } catch (error: CancellationException) {
            if (ownsMutation) mutation.task.cancel()
            throw error
        } finally {
            withContext(NonCancellable) {
                if (ownsMutation && !mutation.task.isCompleted) {
                    mutation.task.join()
                }
                mutationGate.withLock {
                    if (mutations[dataset.stableId] === mutation && mutation.task.isCompleted) {
                        mutations.remove(dataset.stableId)
                    }
                }
            }
        }
    }

    suspend fun cancel(dataset: KnowledgeDatasetConfig): KnowledgeReconciliation {
        val mutation = mutationGate.withLock { mutations[dataset.stableId] }
        mutation?.task?.cancel()
        runCatching { mutation?.task?.await() }
        mutationGate.withLock {
            if (mutations[dataset.stableId] === mutation) {
                mutations.remove(dataset.stableId)
            }
        }
        return reconcile(dataset)
    }

    suspend fun search(
        datasets: List<KnowledgeDatasetConfig>,
        query: List<Float>,
        maxHits: UInt
    ): List<KnowledgePromptHit> = withContext(Dispatchers.IO) {
        indexGate.withLock {
            val merged = mutableListOf<KnowledgePromptHit>()
            for (dataset in datasets) {
                currentCoroutineContext().ensureActive()
                val open = indexes[dataset.stableId] ?: continue
                val hits = try {
                    open.index.search(query, maxHits, dataset.relevanceThreshold)
                } catch (_: Throwable) {
                    continue
                }
                currentCoroutineContext().ensureActive()
                merged += hits.map { hit -> KnowledgePromptHit(dataset.stableId, hit) }
            }
            merged.sortedByDescending { it.hit.score }.take(maxHits.toInt())
        }
    }

    private fun reconcileAndOpenLocked(dataset: KnowledgeDatasetConfig): KnowledgeReconciliation {
        val previous = indexes[dataset.stableId]
        val result = assetStore.reconcileKnowledge(dataset.stableId)
        val directory = result.activeDirectory
        if (directory == null) {
            indexes.remove(dataset.stableId)
            previous?.index?.destroy()
        } else if (previous?.directory != directory) {
            val replacement = RetrievalIndex.open(directory, dataset.stableId)
            indexes[dataset.stableId] = OpenIndex(directory, replacement)
            previous?.index?.destroy()
        }
        result.activeIdentity?.let { activeIdentity ->
            runCatching {
                assetStore.cleanupKnowledgeRevisions(dataset.stableId, activeIdentity)
            }
        }
        return result
    }

    private suspend fun lifecycleGate(stableId: String): Mutex =
        mutationGate.withLock { lifecycleGates.getOrPut(stableId) { Mutex() } }
}

data class KnowledgeDownloadProgress(
    val label: String,
    val percentage: Double
)
