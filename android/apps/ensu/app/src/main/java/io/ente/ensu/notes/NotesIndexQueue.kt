package io.ente.ensu.notes

internal const val NOTES_SCAN_INTERVAL_MS = 300_000L

internal enum class NotesIndexTrigger {
    Maintenance,
    ChangesDetected,
    Manual;

    val waitingStatus: NotesStatus
        get() =
            when (this) {
                Maintenance -> NotesStatus.Pending
                ChangesDetected -> NotesStatus.UpdateScheduled
                Manual -> NotesStatus.UpdateRequested
            }
}

internal class NotesIndexQueue(private val now: () -> Long = System::currentTimeMillis) {
    data class Request(
        val forced: Set<String>,
        val rebuild: Boolean,
        val due: Long,
        val trigger: NotesIndexTrigger,
    )

    private val requests = linkedMapOf<String, Request>()

    operator fun get(id: String) = requests[id]

    operator fun contains(id: String) = id in requests

    fun remove(id: String) = requests.remove(id)

    fun enqueue(
        id: String,
        forced: Set<String> = emptySet(),
        rebuild: Boolean = false,
        changesDetected: Boolean = false,
        immediate: Boolean = false,
    ) {
        val old = requests[id]
        val trigger = old?.trigger ?: NotesIndexTrigger.Maintenance
        requests[id] =
            Request(
                forced = old?.forced.orEmpty() + forced,
                rebuild = rebuild || old?.rebuild == true,
                due = if (immediate) 0 else old?.due ?: (now() + NOTES_SCAN_INTERVAL_MS),
                trigger =
                    if (trigger == NotesIndexTrigger.Maintenance && changesDetected)
                        NotesIndexTrigger.ChangesDetected
                    else trigger,
            )
    }

    fun updateNow(id: String): Boolean {
        val request = requests[id] ?: return false
        if (request.trigger == NotesIndexTrigger.Maintenance) return false
        if (request.trigger == NotesIndexTrigger.Manual && request.due == 0L) return true
        requests[id] = request.copy(due = 0, trigger = NotesIndexTrigger.Manual)
        return true
    }

    fun retry(id: String) {
        if (id !in requests) enqueue(id)
        requests[id]?.let { requests[id] = it.copy(due = 0, trigger = NotesIndexTrigger.Manual) }
    }

    fun defer(id: String) {
        requests[id]?.let { requests[id] = it.copy(due = now() + 30_000) }
    }

    fun next(failed: Set<String>): Map.Entry<String, Request>? =
        requests.entries
            .filter { it.key !in failed && it.value.due <= now() }
            .minByOrNull { if (it.value.trigger == NotesIndexTrigger.Manual) 0 else 1 }

    fun nextDue(failed: Set<String>): Long? =
        requests.filterKeys { it !in failed }.values.minOfOrNull { it.due }

    fun finish(id: String, snapshot: Request) {
        if (requests[id] === snapshot) requests.remove(id)
    }
}
