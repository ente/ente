package io.ente.ensu.notes

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.staticCompositionLocalOf
import io.ente.ensu.bindings.GroundedExcerpt
import io.ente.ensu.bindings.GroundedSource
import io.ente.ensu.bindings.NotePassageLocator
import io.ente.ensu.bindings.NoteSourceReference
import io.ente.ensu.bindings.NotesCancellation
import io.ente.ensu.bindings.NotesException
import io.ente.ensu.bindings.NotesHit
import io.ente.ensu.bindings.NotesIndexOptions
import io.ente.ensu.bindings.NotesProgress
import io.ente.ensu.bindings.NotesProgressCallback
import io.ente.ensu.bindings.NotesSummary
import io.ente.ensu.bindings.notesLimits
import io.ente.ensu.bindings.selectMixedGroundingCandidates
import io.ente.ensu.bindings.withNotesCollectionLabel
import io.ente.ensu.coroutines.runCatchingCancellable
import io.ente.ensu.llm.EmbeddingUse
import io.ente.ensu.llm.LlmProvider
import io.ente.ensu.llm.ModelMaintenance
import io.ente.ensu.llm.ModelMemoryDeferred
import io.ente.ensu.llm.ModelMemoryUnavailable
import io.ente.ensu.llm.withMaintenanceSuspended
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.logging.LogLevel
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class NotesStatus {
    Pending,
    UpdateScheduled,
    UpdateRequested,
    Indexing,
    Updating,
    Ready,
    Unavailable,
    Error,
}

data class NoteCollectionState(
    val id: String,
    val label: String,
    val status: NotesStatus = NotesStatus.Pending,
    val documentCount: Long = 0,
    val indexAvailable: Boolean = false,
    val progress: Int? = null,
    val error: String? = null,
    val completedEmpty: Boolean = false,
    val lastUpdatedAtMs: Long? = null,
) {
    val canRequestUpdate: Boolean
        get() = status == NotesStatus.UpdateScheduled || status == NotesStatus.UpdateRequested

    val eligible: Boolean
        get() = indexAvailable && status != NotesStatus.Error && status != NotesStatus.Unavailable
}

data class NotesState(
    val collections: List<NoteCollectionState> = emptyList(),
    val error: String? = null,
    val inventoryReady: Boolean = false,
    val disabledIds: Set<String> = emptySet(),
)

val LocalNotesStore = staticCompositionLocalOf<NotesStore?> { null }

class NotesStore(
    private val context: Context,
    private val llm: LlmProvider,
    private val logRepository: FileLogRepository,
    private val provider: NotesProvider = NotesProvider(context),
) : ModelMaintenance {
    private enum class IndexFailure {
        SourceAccess,
        Indexing,
    }

    private class Run(
        val cancel: NotesCancellation,
        val job: Job,
    )

    private val limits = notesLimits()
    private val registrations = linkedMapOf<String, NotesRegistration>()
    private val pending = NotesIndexQueue()
    private val scans = linkedSetOf<String>()
    private val failed = mutableMapOf<String, IndexFailure>()
    private val sourceRevisions = mutableMapOf<String, String>()
    private val maintenance = NotesMaintenanceGate<Run>()
    private var scope: CoroutineScope? = null
    private var bootstrapJob: Job? = null
    private val active
        get() = maintenance.active

    private var wake: Job? = null
    private var foreground = false
    private var loaded = false
    private var disabled = false
    private val preferences =
        context.applicationContext.getSharedPreferences("ensu_note_defaults", Context.MODE_PRIVATE)
    private val _state =
        MutableStateFlow(
            NotesState(
                disabledIds = preferences.getStringSet("disabled", emptySet()).orEmpty().toSet()
            )
        )
    val state: StateFlow<NotesState> = _state.asStateFlow()

    fun setEnabled(id: String, enabled: Boolean) {
        val disabledIds = state.value.disabledIds.let { if (enabled) it - id else it + id }
        preferences.edit().putStringSet("disabled", disabledIds).apply()
        _state.update { it.copy(disabledIds = disabledIds) }
    }

    fun bootstrap(owner: CoroutineScope) {
        if (bootstrapJob != null) return
        scope = owner
        bootstrapJob = owner.launch {
            try {
                val records = provider.load()
                registrations.putAll(records.associateBy { it.id })
                val states = records.map { record ->
                    try {
                        val summary = provider.inspect(record.id)
                        if (!summary.initialComplete) enqueue(record.id, immediate = true)
                        fromSummary(record, summary)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: NotesException.RebuildRequired) {
                        enqueue(record.id, rebuild = true, immediate = true)
                        NoteCollectionState(record.id, record.label)
                    } catch (e: Exception) {
                        logRepository.log(
                            LogLevel.Error,
                            "Checkpoint load failed collection=${record.id}",
                            tag = "Notes",
                            throwable = e,
                        )
                        NoteCollectionState(
                            record.id,
                            record.label,
                            NotesStatus.Error,
                            error = message(e),
                        )
                    }
                }
                _state.update { it.copy(collections = states, inventoryReady = true) }
                loaded = true
                scans.addAll(registrations.keys)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                logRepository.log(
                    LogLevel.Error,
                    "Collection registry load failed",
                    tag = "Notes",
                    throwable = e,
                )
                disabled = true
                _state.update {
                    it.copy(
                        error = "Could not load Your Notes. Existing indexes have been preserved."
                    )
                }
            }
            pump()
        }
    }

    suspend fun awaitReady() {
        bootstrapJob?.join()
    }

    fun retryLoad() {
        if (loaded || bootstrapJob?.isActive == true) return
        val owner = scope ?: return
        bootstrapJob = null
        disabled = false
        _state.update { it.copy(error = null) }
        bootstrap(owner)
    }

    fun setForeground(value: Boolean) {
        if (foreground == value) return
        foreground = value
        if (!value) {
            wake?.cancel()
            active?.job?.cancel()
        } else {
            if (loaded) scans.addAll(registrations.keys)
            pump()
        }
    }

    override fun modelReadinessChanged() {
        pump()
    }

    override fun suspendMaintenance(): AutoCloseable {
        maintenance.suspend()?.job?.cancel()
        val closed = AtomicBoolean()
        return AutoCloseable {
            if (closed.compareAndSet(false, true)) {
                maintenance.resume()
                scope?.launch { pump() }
            }
        }
    }

    override suspend fun awaitMaintenance() {
        active?.job?.join()
    }

    fun add(tree: Uri) {
        scope?.launch {
            awaitReady()
            if (disabled) return@launch
            withMaintenanceSuspended {
                try {
                    val record = provider.add(tree)
                    if (record.id !in registrations) setEnabled(record.id, true)
                    registrations[record.id] = record
                    _state.update {
                        it.copy(
                            collections =
                                it.collections + NoteCollectionState(record.id, record.label),
                            error = null,
                        )
                    }
                    enqueue(record.id, immediate = true)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    _state.update { it.copy(error = message(error)) }
                }
            }
        }
    }

    fun remove(id: String) {
        scope?.launch {
            withMaintenanceSuspended {
                if (id !in registrations) return@withMaintenanceSuspended
                try {
                    provider.remove(id)
                    registrations.remove(id)
                    pending.remove(id)
                    scans.remove(id)
                    failed.remove(id)
                    sourceRevisions.remove(id)
                    _state.update {
                        it.copy(
                            collections = it.collections.filter { row -> row.id != id },
                            error = null,
                        )
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    _state.update { it.copy(error = message(error)) }
                }
            }
        }
    }

    fun updateNow(id: String) {
        if (_state.value.collections.none { it.id == id && it.canRequestUpdate }) return
        if (!pending.updateNow(id)) return
        update(id) { it.copy(status = NotesStatus.UpdateRequested) }
        pump()
    }

    fun retry(id: String) {
        if (!loaded || disabled || id !in registrations) return
        if (
            _state.value.collections.none {
                it.id == id &&
                    (it.status == NotesStatus.Error || it.status == NotesStatus.Unavailable)
            }
        )
            return
        failed.remove(id)
        pending.retry(id)
        scans.add(id)
        update(id) { it.copy(status = waitingStatus(id), progress = null, error = null) }
        pump()
    }

    private fun clearError() {
        _state.update { it.copy(error = null) }
    }

    suspend fun retrieve(query: List<Float>, enabledFolderIds: Set<String>): List<NotesHit> =
        withContext(Dispatchers.Main.immediate) {
            val records =
                _state.value.collections
                    .filter { it.eligible && it.id in enabledFolderIds }
                    .mapNotNull { registrations[it.id] }
            val hits = mutableListOf<NotesHit>()
            for (record in records) {
                currentCoroutineContext().ensureActive()
                try {
                    hits += provider.search(record.id, query)
                } catch (error: CancellationException) {
                    throw error
                } catch (_: NotesException.RebuildRequired) {
                    requestRebuild(record.id)
                } catch (error: Exception) {
                    fail(record.id, error)
                }
            }
            hits
        }

    suspend fun reload(locator: NotePassageLocator): GroundedExcerpt? =
        withContext(Dispatchers.Main.immediate) {
            if (_state.value.collections.none { it.id == locator.collectionId && it.eligible })
                return@withContext null
            try {
                val hit = provider.reload(locator) ?: return@withContext null
                verify(selectMixedGroundingCandidates(emptyList(), listOf(hit), 1u)).singleOrNull()
            } catch (_: NotesException.RebuildRequired) {
                requestRebuild(locator.collectionId)
                null
            }
        }

    suspend fun verify(excerpts: List<GroundedExcerpt>): List<GroundedExcerpt> =
        withContext(Dispatchers.Main.immediate) {
            val records = registrations.toMap()
            var accepted = 0
            val result = mutableListOf<GroundedExcerpt>()
            for (excerpt in excerpts) {
                currentCoroutineContext().ensureActive()
                val note = (excerpt.source as? GroundedSource.LocalNote)?.reference
                if (note == null) {
                    result += excerpt
                    continue
                }
                if (accepted.toUInt() >= limits.maxGroundingHits) continue
                val record = records[note.collectionId] ?: continue
                try {
                    provider.verify(note)
                    result +=
                        excerpt.copy(
                            source =
                                GroundedSource.LocalNote(
                                    withNotesCollectionLabel(note, record.label)
                                )
                        )
                    accepted++
                } catch (error: CancellationException) {
                    throw error
                } catch (_: NotesException.SourceChanged) {
                    enqueue(
                        record.id,
                        forced = setOf(note.documentId),
                        changesDetected = true,
                        immediate = true,
                    )
                    if (record.id !in failed) {
                        update(record.id) { it.copy(status = waitingStatus(record.id)) }
                    }
                } catch (error: Exception) {
                    fail(record.id, error)
                }
            }
            result
        }

    fun open(reference: NoteSourceReference) {
        scope?.launch {
            clearError()
            try {
                val uri = withMaintenanceSuspended { provider.preview(reference) }
                context.startActivity(
                    Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "text/plain")
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK
                        )
                    }
                )
                clearError()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error =
                    when (e) {
                        is NotesException.SourceChanged ->
                            "This note changed after the answer was generated."
                        is NotesException.Unavailable -> "This note is unavailable."
                        else ->
                            "Could not open this note. Check folder access and that a text viewer is installed."
                    }
                _state.update { it.copy(error = error) }
            }
        }
    }

    private fun requestRebuild(id: String) {
        enqueue(id, rebuild = true, immediate = true)
        update(id) {
            it.copy(
                status = if (id in failed) it.status else waitingStatus(id),
                indexAvailable = false,
            )
        }
    }

    private fun waitingStatus(id: String) =
        pending[id]?.trigger?.waitingStatus ?: NotesStatus.Pending

    private fun keepIndexFailure(id: String, revision: String?): Boolean {
        if (failed[id] != IndexFailure.Indexing) return false
        val previous = sourceRevisions[id]
        revision?.let { sourceRevisions[id] = it }
        return revision == null || previous == null || revision == previous
    }

    private suspend fun recoverRebuild(id: String) {
        requestRebuild(id)
        val revision =
            try {
                NotesCancellation().use { provider.inspectSourceRevision(id, it) }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                return
            }
        val failure = failed[id] ?: return
        if (keepIndexFailure(id, revision)) return
        failed.remove(id)
        val previous = pending.remove(id)
        revision?.let { sourceRevisions[id] = it }
        enqueue(
            id,
            forced = previous?.forced.orEmpty(),
            rebuild = true,
            changesDetected = failure == IndexFailure.Indexing,
            immediate = failure == IndexFailure.SourceAccess,
        )
        update(id) {
            it.copy(
                status = waitingStatus(id),
                progress = null,
                error = null,
                indexAvailable = false,
            )
        }
    }

    private fun enqueue(
        id: String,
        rebuild: Boolean = false,
        forced: Set<String> = emptySet(),
        changesDetected: Boolean = false,
        immediate: Boolean = false,
    ) {
        if (id !in registrations) return
        pending.enqueue(id, forced, rebuild, changesDetected, immediate)
    }

    private fun pump() {
        val owner = scope ?: return
        if (!owner.isActive || !loaded || disabled || !foreground || !maintenance.available) return
        wake?.cancel()
        val now = System.currentTimeMillis()
        val embeddingReady = llm.isEmbeddingModelReady()
        val request =
            if (embeddingReady) {
                pending.next(failed.keys)
            } else null
        val id = request?.key ?: scans.firstOrNull { it !in pending || it in failed }
        if (id == null) {
            val due =
                if (embeddingReady) {
                    pending.nextDue(failed.keys)
                } else null
            wake = owner.launch {
                delay(
                    minOf(
                        NOTES_SCAN_INTERVAL_MS,
                        due?.minus(now)?.coerceAtLeast(1) ?: NOTES_SCAN_INTERVAL_MS,
                    )
                )
                scans.addAll(_state.value.collections.map { it.id })
                pump()
            }
            return
        }
        val record =
            registrations[id]
                ?: run {
                    pending.remove(id)
                    scans.remove(id)
                    pump()
                    return
                }
        val snapshot = request?.value
        val cancel = NotesCancellation()
        val hadIndex = _state.value.collections.firstOrNull { it.id == id }?.indexAvailable == true
        val job =
            owner.launch(start = CoroutineStart.LAZY) {
                scans.remove(id)
                var completed = false
                var failure: Throwable? = null
                try {
                    cancel.check()
                    if (snapshot == null) {
                        val result =
                            try {
                                provider.inspectFreshness(id, cancel)
                            } catch (error: NotesException.RebuildRequired) {
                                if (id !in failed) throw error
                                recoverRebuild(id)
                                completed = true
                                return@launch
                            }
                        val previous =
                            failed[id]?.let {
                                if (keepIndexFailure(id, result.sourceRevision)) {
                                    completed = true
                                    return@launch
                                }
                                failed.remove(id)
                                pending.remove(id)
                            }
                        result.sourceRevision?.let { sourceRevisions[id] = it }
                        if (result.changed || previous?.rebuild == true) {
                            enqueue(
                                id,
                                forced = previous?.forced.orEmpty() + result.forcedDocumentIds,
                                rebuild = previous?.rebuild == true,
                                changesDetected = result.summary.initialComplete,
                                immediate = !result.summary.initialComplete,
                            )
                        }
                        update(id) {
                            val refreshed = fromSummary(record, result.summary)
                            refreshed.copy(
                                status = if (id in pending) waitingStatus(id) else refreshed.status,
                                error = if (id in pending) null else refreshed.error,
                                progress =
                                    if (result.summary.initialComplete) null else it.progress,
                                indexAvailable =
                                    refreshed.indexAvailable && pending[id]?.rebuild != true,
                            )
                        }
                    } else {
                        update(id) {
                            it.copy(
                                status =
                                    if (hadIndex) NotesStatus.Updating else NotesStatus.Indexing,
                                error = null,
                            )
                        }
                        sourceRevisions.remove(id)
                        val result =
                            llm.withEmbeddingContext(
                                use =
                                    if (snapshot.trigger == NotesIndexTrigger.Manual)
                                        EmbeddingUse.ManualIndexing
                                    else EmbeddingUse.AutomaticIndexing,
                                checkCancellation = cancel::check,
                            ) { embedding ->
                                val forced = snapshot.forced.toMutableSet()
                                val revision =
                                    try {
                                        val freshness =
                                            NotesCancellation().use { freshnessCancellation ->
                                                provider.inspectFreshness(id, freshnessCancellation)
                                            }
                                        forced.addAll(freshness.forcedDocumentIds)
                                        freshness.sourceRevision
                                    } catch (_: NotesException.RebuildRequired) {
                                        NotesCancellation().use { revisionCancellation ->
                                            provider.inspectSourceRevision(id, revisionCancellation)
                                        }
                                    }
                                revision?.let {
                                    withContext(Dispatchers.Main.immediate) {
                                        sourceRevisions[id] = it
                                    }
                                }
                                provider.index(
                                    id,
                                    embedding,
                                    cancel,
                                    object : NotesProgressCallback {
                                        override fun onProgress(progress: NotesProgress) {
                                            owner.launch {
                                                if (active?.cancel === cancel) {
                                                    update(id) {
                                                        it.copy(
                                                            progress = progress.percentage.toInt(),
                                                            documentCount =
                                                                progress.indexedDocumentCount
                                                                    .toLong(),
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                    },
                                    NotesIndexOptions(forced.toList(), snapshot.rebuild),
                                )
                            }
                        val changedId = result.changedDocumentId
                        pending.finish(id, snapshot)
                        if (changedId != null) {
                            enqueue(
                                id,
                                forced = result.uncheckedDocumentIds.toSet() + changedId,
                                changesDetected = result.summary.initialComplete,
                            )
                        }
                        update(id) {
                            if (id !in pending) {
                                fromSummary(record, result.summary)
                            } else {
                                it.copy(
                                    status = waitingStatus(id),
                                    progress = null,
                                    lastUpdatedAtMs = result.summary.lastUpdatedAtMs,
                                    documentCount = result.summary.documentCount.toLong(),
                                    indexAvailable =
                                        hadIndex &&
                                            result.summary.initialComplete &&
                                            result.summary.documentCount > 0uL &&
                                            pending[id]?.rebuild != true,
                                )
                            }
                        }
                    }
                    completed = true
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    failure = error
                } catch (error: Throwable) {
                    failure = error
                    throw error
                } finally {
                    if (!completed && !(snapshot == null && id in failed)) {
                        when (failure) {
                            is ModelMemoryDeferred -> {
                                pending.defer(id)
                                update(id) { it.copy(status = waitingStatus(id), progress = null) }
                            }
                            null,
                            is NotesException.Cancelled -> {
                                if (snapshot == null) scans.add(id)
                                val saved =
                                    withContext(NonCancellable) {
                                        runCatchingCancellable { provider.inspect(id) }.getOrNull()
                                    }
                                update(id) {
                                    it.copy(
                                        status = waitingStatus(id),
                                        progress = null,
                                        lastUpdatedAtMs =
                                            saved?.lastUpdatedAtMs ?: it.lastUpdatedAtMs,
                                        indexAvailable =
                                            hadIndex &&
                                                saved?.initialComplete == true &&
                                                saved.documentCount > 0uL &&
                                                pending[id]?.rebuild != true,
                                    )
                                }
                            }
                            is NotesException.RebuildRequired -> {
                                if (snapshot == null) {
                                    requestRebuild(id)
                                } else fail(id, failure)
                            }
                            is Exception -> {
                                if (
                                    snapshot != null ||
                                        pending[id]?.trigger != NotesIndexTrigger.Manual
                                ) {
                                    fail(id, failure)
                                }
                            }
                        }
                    }
                }
            }
        val run = Run(cancel, job)
        val admitted = maintenance.admit(run)
        job.invokeOnCompletion {
            cancel.destroy()
            maintenance.finish(run)
            if (admitted) owner.launch { pump() }
        }
        if (admitted) job.start() else job.cancel()
    }

    private fun fail(id: String, e: Exception) {
        if (id !in registrations) return
        logRepository.log(
            LogLevel.Error,
            "Notes update failed collection=$id",
            tag = "Notes",
            throwable = e,
        )
        failed[id] =
            if (
                e is NotesException.Unavailable ||
                    e is NotesException.SourceRead ||
                    e is NotesException.SourceChanged
            )
                IndexFailure.SourceAccess
            else IndexFailure.Indexing
        scans.remove(id)
        update(id) {
            it.copy(
                status =
                    if (e is NotesException.Unavailable) NotesStatus.Unavailable
                    else NotesStatus.Error,
                progress = null,
                error = message(e),
                completedEmpty = false,
            )
        }
    }

    private fun update(id: String, transform: (NoteCollectionState) -> NoteCollectionState) {
        _state.update {
            it.copy(
                collections =
                    it.collections.map { row -> if (row.id == id) transform(row) else row }
            )
        }
    }

    private fun fromSummary(record: NotesRegistration, summary: NotesSummary): NoteCollectionState {
        val ready = summary.initialComplete && summary.documentCount > 0uL
        val empty = summary.initialComplete && !ready
        return NoteCollectionState(
            id = record.id,
            label = record.label,
            status =
                when {
                    ready -> NotesStatus.Ready
                    empty -> NotesStatus.Error
                    else -> NotesStatus.Pending
                },
            documentCount = summary.documentCount.toLong(),
            indexAvailable = ready,
            error = if (empty) EMPTY_NOTES else null,
            completedEmpty = empty,
            lastUpdatedAtMs = summary.lastUpdatedAtMs,
        )
    }

    private fun message(e: Exception): String =
        when (e) {
            is ModelMemoryUnavailable -> e.message.orEmpty()
            is NotesException.Unavailable ->
                "This Notes folder is unavailable. Check access and try again."
            is NotesException.SourceChanged ->
                "The folder changed. Try again after it finishes updating."
            is NotesException.SourceRead -> e.detail
            is NotesException.InvalidInput -> e.detail
            is NotesException.Storage ->
                "Could not save the Notes index. Check storage and try again."
            is NotesException.RebuildRequired -> "The Notes index needs rebuilding."
            else -> "Could not update Your Notes. Please try again."
        }

    companion object {
        private const val EMPTY_NOTES = "No supported non-empty UTF-8 notes were found"
    }
}
