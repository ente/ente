package io.ente.ensu.notes

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.staticCompositionLocalOf
import io.ente.ensu.bindings.GroundedExcerpt
import io.ente.ensu.bindings.GroundedSource
import io.ente.ensu.bindings.NoteSourceReference
import io.ente.ensu.bindings.NotesCancellation
import io.ente.ensu.bindings.NotesException
import io.ente.ensu.bindings.NotesHit
import io.ente.ensu.bindings.NotesIndexOptions
import io.ente.ensu.bindings.NotesProgress
import io.ente.ensu.bindings.NotesProgressCallback
import io.ente.ensu.bindings.NotesSummary
import io.ente.ensu.bindings.notesLimits
import io.ente.ensu.bindings.withNotesCollectionLabel
import io.ente.ensu.llm.LlmProvider
import io.ente.ensu.llm.ModelMaintenance
import io.ente.ensu.llm.withMaintenanceSuspended
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.logging.LogLevel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.util.concurrent.atomic.AtomicBoolean

enum class NotesStatus { Pending, Indexing, Updating, Ready, Unavailable, Error }

data class NoteCollectionState(
    val id: String,
    val label: String,
    val status: NotesStatus = NotesStatus.Pending,
    val documentCount: Long = 0,
    val indexAvailable: Boolean = false,
    val progress: Int? = null,
    val error: String? = null,
    val completedEmpty: Boolean = false,
    val lastUpdatedAtMs: Long? = null
) {
    val eligible: Boolean
        get() = indexAvailable && status != NotesStatus.Error && status != NotesStatus.Unavailable
}

data class NotesState(
    val collections: List<NoteCollectionState> = emptyList(),
    val error: String? = null
)

val LocalNotesStore = staticCompositionLocalOf<NotesStore?> { null }

class NotesStore(
    private val context: Context,
    private val llm: LlmProvider,
    private val logRepository: FileLogRepository,
    private val provider: NotesProvider = NotesProvider(context)
) : ModelMaintenance {
    private data class Pending(
        val forced: Set<String>,
        val rebuild: Boolean,
        val due: Long
    )

    private class Run(
        val cancel: NotesCancellation,
        val job: Job
    )

    private val limits = notesLimits()
    private val registrations = linkedMapOf<String, NotesRegistration>()
    private val pending = linkedMapOf<String, Pending>()
    private val scans = linkedSetOf<String>()
    private val failed = mutableSetOf<String>()
    private val maintenance = NotesMaintenanceGate<Run>()
    private var scope: CoroutineScope? = null
    private var bootstrapJob: Job? = null
    private val active get() = maintenance.active
    private var wake: Job? = null
    private var foreground = false
    private var loaded = false
    private var disabled = false
    private val _state = MutableStateFlow(NotesState())
    val state: StateFlow<NotesState> = _state.asStateFlow()

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
                    } catch (e: NotesException.RebuildRequired) {
                        enqueue(record.id, rebuild = true, immediate = true)
                        NoteCollectionState(record.id, record.label)
                    } catch (e: Exception) {
                        logRepository.log(LogLevel.Error, "Checkpoint load failed collection=${record.id}", tag = "Notes", throwable = e)
                        NoteCollectionState(record.id, record.label, NotesStatus.Error, error = message(e))
                    }
                }
                _state.value = NotesState(states)
                loaded = true
                scans.addAll(registrations.keys)
            } catch (e: Exception) {
                logRepository.log(LogLevel.Error, "Collection registry load failed", tag = "Notes", throwable = e)
                disabled = true
                _state.value = NotesState(error = "Could not load Your Notes. Existing indexes have been preserved.")
            }
            pump()
        }
    }

    suspend fun awaitReady() {
        bootstrapJob?.join()
    }

    fun setForeground(value: Boolean) {
        if (foreground == value) return
        foreground = value
        if (!value) {
            wake?.cancel()
            active?.job?.cancel()
        } else {
            failed.clear()
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
                    registrations[record.id] = record
                    _state.update {
                        it.copy(collections = it.collections + NoteCollectionState(record.id, record.label), error = null)
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
                    _state.update {
                        it.copy(collections = it.collections.filter { row -> row.id != id }, error = null)
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    _state.update { it.copy(error = message(error)) }
                }
            }
        }
    }

    fun retry(id: String) {
        if (!loaded || disabled || id !in registrations) return
        failed.remove(id)
        pending[id]?.let { pending[id] = it.copy(due = 0) }
        scans.add(id)
        update(id) { it.copy(status = NotesStatus.Pending, progress = null, error = null) }
        pump()
    }

    private fun clearError() {
        _state.update { it.copy(error = null) }
    }

    suspend fun retrieve(query: List<Float>): List<NotesHit> = withContext(Dispatchers.Main.immediate) {
        val records = _state.value.collections.filter { it.eligible }.mapNotNull { registrations[it.id] }
        val hits = mutableListOf<NotesHit>()
        for (record in records) {
            currentCoroutineContext().ensureActive()
            try {
                hits += provider.search(record.id, query)
            } catch (error: CancellationException) {
                throw error
            } catch (error: NotesException.RebuildRequired) {
                enqueue(record.id, rebuild = true, immediate = true)
                update(record.id) { it.copy(status = NotesStatus.Pending, indexAvailable = false) }
            } catch (error: Exception) {
                fail(record.id, error)
            }
        }
        hits
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
                    result += excerpt.copy(source = GroundedSource.LocalNote(withNotesCollectionLabel(note, record.label)))
                    accepted++
                } catch (error: CancellationException) {
                    throw error
                } catch (error: NotesException.SourceChanged) {
                    enqueue(record.id, forced = setOf(note.documentId), immediate = true)
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
                val uri = withMaintenanceSuspended {
                    provider.preview(reference)
                }
                context.startActivity(Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "text/plain")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                })
                clearError()
            } catch (e: Exception) {
                val error = when (e) {
                    is NotesException.SourceChanged -> "This note changed after the answer was generated."
                    is NotesException.Unavailable -> "This note is unavailable."
                    else -> "Could not open this note. Check folder access and that a text viewer is installed."
                }
                _state.update { it.copy(error = error) }
            }
        }
    }

    private fun enqueue(
        id: String,
        rebuild: Boolean = false,
        forced: Set<String> = emptySet(),
        immediate: Boolean = false
    ) {
        if (id !in registrations) return
        val old = pending[id]
        pending[id] = Pending(
            forced = old?.forced.orEmpty() + forced,
            rebuild = rebuild || old?.rebuild == true,
            due = if (immediate) 0 else old?.due ?: (System.currentTimeMillis() + SCAN_INTERVAL_MS)
        )
    }

    private fun pump() {
        val owner = scope ?: return
        if (!owner.isActive || !loaded || disabled || !foreground || !maintenance.available) return
        wake?.cancel()
        val now = System.currentTimeMillis()
        val embeddingReady = llm.isEmbeddingModelReady()
        val request = if (embeddingReady) {
            pending.entries.firstOrNull { it.key !in failed && it.value.due <= now }
        } else null
        val id = request?.key ?: scans.firstOrNull { it !in pending && it !in failed }
        if (id == null) {
            val due = if (embeddingReady) {
                pending.asSequence().filter { it.key !in failed }.minOfOrNull { it.value.due }
            } else null
            wake = owner.launch {
                delay(minOf(SCAN_INTERVAL_MS, due?.minus(now)?.coerceAtLeast(1) ?: SCAN_INTERVAL_MS))
                scans.addAll(_state.value.collections.filter {
                    it.status != NotesStatus.Unavailable && (it.status != NotesStatus.Error || it.completedEmpty)
                }.map { it.id })
                pump()
            }
            return
        }
        val record = registrations[id] ?: run {
            pending.remove(id)
            scans.remove(id)
            pump()
            return
        }
        val snapshot = request?.value
        val cancel = NotesCancellation()
        val hadIndex = _state.value.collections.firstOrNull { it.id == id }?.indexAvailable == true
        val job = owner.launch(start = CoroutineStart.LAZY) {
            scans.remove(id)
            try {
                cancel.check()
                if (snapshot == null) {
                    val result = provider.inspectFreshness(id, cancel)
                    update(id) { fromSummary(record, result.summary).copy(progress = if (result.summary.initialComplete) null else it.progress) }
                    if (result.changed) {
                        enqueue(id, forced = result.forcedDocumentIds.toSet(), immediate = !result.summary.initialComplete)
                        update(id) { it.copy(status = NotesStatus.Pending, error = null) }
                    }
                } else {
                    update(id) { it.copy(status = if (hadIndex) NotesStatus.Updating else NotesStatus.Indexing, error = null) }
                    val result = llm.withEmbeddingContext(checkCancellation = cancel::check) { embedding ->
                        provider.index(
                            id,
                            embedding,
                            cancel,
                            object : NotesProgressCallback {
                                override fun onProgress(progress: NotesProgress) {
                                    owner.launch {
                                        if (active?.cancel === cancel) {
                                            update(id) {
                                                it.copy(progress = progress.percentage.toInt(), documentCount = progress.indexedDocumentCount.toLong())
                                            }
                                        }
                                    }
                                }
                            },
                            NotesIndexOptions(snapshot.forced.toList(), snapshot.rebuild)
                        )
                    }
                    val changedId = result.changedDocumentId
                    if (pending[id] === snapshot) {
                        if (changedId == null) {
                            pending.remove(id)
                        } else {
                            pending[id] = snapshot.copy(
                                forced = result.uncheckedDocumentIds.toSet() + changedId,
                                rebuild = false,
                                due = System.currentTimeMillis() + SCAN_INTERVAL_MS
                            )
                        }
                    } else if (changedId != null) {
                        enqueue(id, forced = result.uncheckedDocumentIds.toSet() + changedId)
                    }
                    update(id) {
                        if (id !in pending) {
                            fromSummary(record, result.summary)
                        } else {
                            it.copy(
                                status = NotesStatus.Pending,
                                documentCount = result.summary.documentCount.toLong(),
                                indexAvailable = hadIndex && result.summary.initialComplete && result.summary.documentCount > 0uL
                            )
                        }
                    }
                }
            } catch (e: Exception) {
                when (e) {
                    is NotesException.Cancelled, is CancellationException -> {
                        if (snapshot == null) scans.add(id)
                        val saved = withContext(NonCancellable) {
                            runCatching { provider.inspect(id) }.getOrNull()
                        }
                        update(id) {
                            it.copy(
                                status = NotesStatus.Pending,
                                indexAvailable = hadIndex && saved?.initialComplete == true && saved.documentCount > 0uL
                            )
                        }
                        if (e is CancellationException) throw e
                    }
                    is NotesException.RebuildRequired -> {
                        if (snapshot == null) {
                            enqueue(id, rebuild = true, immediate = true)
                            update(id) { it.copy(status = NotesStatus.Pending, indexAvailable = false) }
                        } else fail(id, e)
                    }
                    else -> fail(id, e)
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
        logRepository.log(LogLevel.Error, "Notes update failed collection=$id", tag = "Notes", throwable = e)
        failed.add(id)
        scans.remove(id)
        update(id) {
            it.copy(
                status = if (e is NotesException.Unavailable) NotesStatus.Unavailable else NotesStatus.Error,
                progress = null,
                error = message(e),
                completedEmpty = false
            )
        }
    }

    private fun update(id: String, transform: (NoteCollectionState) -> NoteCollectionState) {
        _state.update { it.copy(collections = it.collections.map { row -> if (row.id == id) transform(row) else row }) }
    }

    private fun fromSummary(record: NotesRegistration, summary: NotesSummary): NoteCollectionState {
        val ready = summary.initialComplete && summary.documentCount > 0uL
        val empty = summary.initialComplete && !ready
        return NoteCollectionState(
            id = record.id,
            label = record.label,
            status = when {
                ready -> NotesStatus.Ready
                empty -> NotesStatus.Error
                else -> NotesStatus.Pending
            },
            documentCount = summary.documentCount.toLong(),
            indexAvailable = ready,
            error = if (empty) EMPTY_NOTES else null,
            completedEmpty = empty,
            lastUpdatedAtMs = summary.lastUpdatedAtMs
        )
    }

    private fun message(e: Exception): String = when (e) {
        is NotesException.Unavailable -> "This Notes folder is unavailable. Check access and try again."
        is NotesException.SourceChanged -> "The folder changed. Try again after it finishes updating."
        is NotesException.SourceRead -> e.detail
        is NotesException.InvalidInput -> e.detail
        is NotesException.Storage -> "Could not save the Notes index. Check storage and try again."
        is NotesException.RebuildRequired -> "The Notes index needs rebuilding."
        else -> "Could not update Your Notes. Please try again."
    }

    companion object {
        private const val SCAN_INTERVAL_MS = 300_000L
        private const val EMPTY_NOTES = "No supported non-empty UTF-8 notes were found"
    }
}
