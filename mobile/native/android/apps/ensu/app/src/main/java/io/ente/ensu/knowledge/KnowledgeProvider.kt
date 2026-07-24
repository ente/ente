package io.ente.ensu.knowledge

import io.ente.ensu.bindings.CancellationToken
import io.ente.ensu.bindings.KnowledgeDatasetConfig
import io.ente.ensu.bindings.KnowledgeDownloadCallback
import io.ente.ensu.bindings.KnowledgeDownloadProgress
import io.ente.ensu.bindings.KnowledgePromptHit
import io.ente.ensu.bindings.KnowledgeReconciliation
import io.ente.ensu.bindings.RetrievalIndex
import io.ente.ensu.bindings.cleanupObsoleteKnowledgePackRevisions
import io.ente.ensu.bindings.downloadKnowledgePack
import io.ente.ensu.bindings.reconcileKnowledgePack
import java.io.File
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
    private val knowledgeRoot: File
) {
    private data class ActiveMutation(
        val cancellation: CancellationToken,
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
                    val cancellation = CancellationToken()
                    val task = async(Dispatchers.IO) {
                        try {
                            downloadKnowledgePack(
                                packRoot(dataset).absolutePath,
                                dataset.stableId,
                                object : KnowledgeDownloadCallback {
                                    override fun onProgress(progress: KnowledgeDownloadProgress) {
                                        onProgress(progress)
                                    }
                                },
                                cancellation
                            )
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
                                    incomingRevision(dataset).deleteRecursively()
                                    runCatching { reconcileAndOpenLocked(dataset) }
                                }
                            }
                            throw error
                        }
                    }
                    ActiveMutation(cancellation, task).also {
                        mutations[dataset.stableId] = it
                    }
                }
            }
        }

        try {
            mutation.task.await()
        } catch (error: CancellationException) {
            if (ownsMutation) mutation.cancellation.cancel()
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
        mutation?.cancellation?.cancel()
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
        val root = packRoot(dataset).absolutePath
        val result = reconcileKnowledgePack(root, dataset.stableId)
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
                cleanupObsoleteKnowledgePackRevisions(root, dataset.stableId, activeIdentity)
            }
        }
        return result
    }

    private fun packRoot(dataset: KnowledgeDatasetConfig): File =
        File(knowledgeRoot, dataset.stableId)

    private fun incomingRevision(dataset: KnowledgeDatasetConfig): File =
        File(packRoot(dataset), dataset.currentDownloadIdentity)

    private suspend fun lifecycleGate(stableId: String): Mutex =
        mutationGate.withLock { lifecycleGates.getOrPut(stableId) { Mutex() } }
}
